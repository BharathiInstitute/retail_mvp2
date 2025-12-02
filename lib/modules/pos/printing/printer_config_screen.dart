// Printer Settings Screen - FREE Options Only
// Configure local USB/WiFi printing without any paid services
// 
// Options:
// 1. Local Backend (USB printer on same network) - FREE
// 2. Browser Print Dialog - FREE
// 3. Page size and format settings

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/theme/theme_extension_helpers.dart';
import '../../stores/providers.dart';
import 'cloud_printer_settings.dart';
import 'print_settings.dart';

/// Get the auto-detected printer backend URL based on current host
String _getAutoBackendUrl() {
  if (kIsWeb) {
    // On web, we can access Uri.base to get current host
    try {
      final uri = Uri.base;
      final host = uri.host;
      // If accessing via localhost or 127.0.0.1, use localhost
      if (host == 'localhost' || host == '127.0.0.1') {
        return 'http://localhost:5005';
      }
      // If accessing via IP (e.g., 192.168.x.x), use same IP for backend
      if (host.isNotEmpty) {
        return 'http://$host:5005';
      }
    } catch (_) {}
  }
  return 'http://localhost:5005';
}

/// Provider for printer settings stream
final printerSettingsProvider = StreamProvider.family<CloudPrinterSettings, String>((ref, storeId) {
  return CloudPrinterSettingsRepository(storeId: storeId).stream();
});

/// Print method options - ALL FREE
enum PrintMethodOption {
  localUsb,      // USB printer via local backend
  localWifi,     // WiFi/Network printer via local backend  
  browserPrint,  // Browser print dialog
}

/// Printer connection type
enum PrinterConnectionType {
  usb,
  wifi,
  network,
  local,
  virtual,
  unknown,
}

/// Printer type
enum PrinterType {
  thermal,
  standard,
  virtual,
}

/// Detailed printer info from backend
class PrinterInfo {
  final String name;
  final PrinterConnectionType connectionType;
  final PrinterType printerType;
  final bool isDefault;
  final String status;
  final bool connected;
  
  PrinterInfo({
    required this.name,
    required this.connectionType,
    required this.printerType,
    required this.isDefault,
    required this.status,
    required this.connected,
  });
  
  factory PrinterInfo.fromJson(Map<String, dynamic> json) {
    return PrinterInfo(
      name: json['name'] as String? ?? '',
      connectionType: _parseConnectionType(json['connectionType'] as String?),
      printerType: _parsePrinterType(json['printerType'] as String?),
      isDefault: json['isDefault'] as bool? ?? false,
      status: json['status'] as String? ?? 'unknown',
      connected: json['connected'] as bool? ?? true,
    );
  }
  
  static PrinterConnectionType _parseConnectionType(String? type) {
    switch (type) {
      case 'usb': return PrinterConnectionType.usb;
      case 'wifi': return PrinterConnectionType.wifi;
      case 'network': return PrinterConnectionType.network;
      case 'local': return PrinterConnectionType.local;
      case 'virtual': return PrinterConnectionType.virtual;
      default: return PrinterConnectionType.unknown;
    }
  }
  
  static PrinterType _parsePrinterType(String? type) {
    switch (type) {
      case 'thermal': return PrinterType.thermal;
      case 'virtual': return PrinterType.virtual;
      default: return PrinterType.standard;
    }
  }
  
  /// Get status display text
  String get statusLabel {
    switch (status) {
      case 'ready': return 'Ready';
      case 'offline': return 'Offline';
      case 'error': return 'Error';
      case 'paused': return 'Paused';
      case 'paper_jam': return 'Paper Jam';
      case 'paper_out': return 'Out of Paper';
      case 'paper_problem': return 'Paper Problem';
      case 'busy': return 'Busy';
      case 'printing': return 'Printing';
      case 'warming_up': return 'Warming Up';
      case 'toner_low': return 'Low Toner';
      case 'door_open': return 'Door Open';
      case 'not_available': return 'Not Available';
      default: return status.replaceAll('_', ' ').toUpperCase();
    }
  }
  
  /// Get status color
  Color get statusColor {
    if (!connected) return Colors.red;
    switch (status) {
      case 'ready': return Colors.green;
      case 'printing':
      case 'busy':
      case 'warming_up': return Colors.blue;
      case 'paused': return Colors.orange;
      case 'paper_jam':
      case 'paper_out':
      case 'paper_problem':
      case 'toner_low':
      case 'door_open': return Colors.orange;
      case 'offline':
      case 'error':
      case 'not_available': return Colors.red;
      default: return Colors.grey;
    }
  }
  
  IconData get connectionIcon {
    switch (connectionType) {
      case PrinterConnectionType.usb: return Icons.usb;
      case PrinterConnectionType.wifi: return Icons.wifi;
      case PrinterConnectionType.network: return Icons.lan;
      case PrinterConnectionType.local: return Icons.computer;
      case PrinterConnectionType.virtual: return Icons.picture_as_pdf;
      case PrinterConnectionType.unknown: return Icons.print;
    }
  }
  
  String get connectionLabel {
    switch (connectionType) {
      case PrinterConnectionType.usb: return 'USB';
      case PrinterConnectionType.wifi: return 'WiFi';
      case PrinterConnectionType.network: return 'Network';
      case PrinterConnectionType.local: return 'Local';
      case PrinterConnectionType.virtual: return 'Virtual';
      case PrinterConnectionType.unknown: return 'Unknown';
    }
  }
  
  Color get connectionColor {
    switch (connectionType) {
      case PrinterConnectionType.usb: return Colors.blue;
      case PrinterConnectionType.wifi: return Colors.green;
      case PrinterConnectionType.network: return Colors.orange;
      case PrinterConnectionType.local: return Colors.purple;
      case PrinterConnectionType.virtual: return Colors.grey;
      case PrinterConnectionType.unknown: return Colors.grey;
    }
  }
  
  IconData get typeIcon {
    switch (printerType) {
      case PrinterType.thermal: return Icons.receipt;
      case PrinterType.virtual: return Icons.picture_as_pdf;
      case PrinterType.standard: return Icons.print;
    }
  }
  
  String get typeLabel {
    switch (printerType) {
      case PrinterType.thermal: return 'Thermal Receipt';
      case PrinterType.virtual: return 'Virtual';
      case PrinterType.standard: return 'Standard';
    }
  }
}

class PrinterSettingsScreen extends ConsumerStatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  ConsumerState<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends ConsumerState<PrinterSettingsScreen> {
  // State
  bool _loading = false;
  String? _error;
  String? _success;
  
  // Local Backend state
  bool _localBackendAvailable = false;
  bool _testingLocal = false;
  bool _loadingPrinters = false;
  List<PrinterInfo> _localPrinters = [];
  String? _selectedPrinter;
  late final TextEditingController _backendUrlCtrl;
  
  // Page settings
  String _paperSize = '58mm';  // 58mm, 80mm, A4
  int _charWidth = 32;
  int _fontSize = 9;
  
  CloudPrinterSettingsRepository? _repo;

  @override
  void initState() {
    super.initState();
    // Auto-detect backend URL based on current host
    _backendUrlCtrl = TextEditingController(text: _getAutoBackendUrl());
    _loadLocalSettings();
    _testLocalBackend();
  }

  @override
  void dispose() {
    _backendUrlCtrl.dispose();
    super.dispose();
  }
  
  void _loadLocalSettings() {
    // Load from global print settings
    final settings = globalPrintSettings;
    _paperSize = settings.paperWidthMm == 58 ? '58mm' : (settings.paperWidthMm == 80 ? '80mm' : 'A4');
    _charWidth = settings.receiptCharWidth;
    _fontSize = settings.fontSizePt;
  }

  // ==================== Local Backend Methods ====================
  
  Future<void> _testLocalBackend() async {
    final url = _backendUrlCtrl.text.trim();
    if (url.isEmpty) return;
    
    setState(() {
      _testingLocal = true;
      _error = null;
    });
    
    try {
      final response = await http.get(Uri.parse('$url/health'))
          .timeout(const Duration(seconds: 3));
      
      if (response.statusCode == 200) {
        setState(() {
          _localBackendAvailable = true;
          _testingLocal = false;
          _success = 'Connected to local printer service!';
        });
        _loadLocalPrinters();
      } else {
        setState(() {
          _localBackendAvailable = false;
          _testingLocal = false;
        });
      }
    } catch (e) {
      setState(() {
        _localBackendAvailable = false;
        _testingLocal = false;
      });
    }
  }
  
  Future<void> _loadLocalPrinters() async {
    final url = _backendUrlCtrl.text.trim();
    setState(() => _loadingPrinters = true);
    
    try {
      final response = await http.get(Uri.parse('$url/printers'))
          .timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final printersList = data['printers'] as List? ?? [];
        final printers = printersList
            .map((p) => PrinterInfo.fromJson(p as Map<String, dynamic>))
            .toList();
        final defaultPrinter = data['defaultPrinter'] as String?;
        
        setState(() {
          _localPrinters = printers;
          _loadingPrinters = false;
          if (defaultPrinter != null) {
            _selectedPrinter = defaultPrinter;
          } else if (printers.isNotEmpty && _selectedPrinter == null) {
            _selectedPrinter = printers.first.name;
          }
        });
      } else {
        setState(() => _loadingPrinters = false);
      }
    } catch (e) {
      setState(() => _loadingPrinters = false);
    }
  }
  
  Future<void> _setDefaultPrinter(String printerName) async {
    final url = _backendUrlCtrl.text.trim();
    try {
      await http.post(
        Uri.parse('$url/set-default'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'printer': printerName}),
      );
      setState(() {
        _selectedPrinter = printerName;
        // Update isDefault flag in local list
        for (var i = 0; i < _localPrinters.length; i++) {
          final p = _localPrinters[i];
          _localPrinters[i] = PrinterInfo(
            name: p.name,
            connectionType: p.connectionType,
            printerType: p.printerType,
            isDefault: p.name == printerName,
            status: p.status,
            connected: p.connected,
          );
        }
        _success = 'Default printer set to: $printerName';
      });
    } catch (e) {
      setState(() => _error = 'Failed to set printer: $e');
    }
  }
  
  Future<void> _testPrint() async {
    final url = _backendUrlCtrl.text.trim();
    
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    
    try {
      final response = await http.post(
        Uri.parse('$url/print-invoice'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'invoice': {
            'invoiceNumber': 'TEST-${DateTime.now().millisecondsSinceEpoch}',
            'timestamp': DateTime.now().toIso8601String(),
            'customerName': 'Test Customer',
            'lines': [
              {'name': 'Test Product 1', 'qty': 2, 'unitPrice': 50, 'lineTotal': 100},
              {'name': 'Test Product 2', 'qty': 1, 'unitPrice': 75, 'lineTotal': 75},
            ],
            'subtotal': 175,
            'discountTotal': 0,
            'taxTotal': 0,
            'grandTotal': 175,
            'paymentMode': 'cash',
            'redeemedValue': 0,
          }
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        setState(() {
          _loading = false;
          _success = 'Test print sent to ${_selectedPrinter ?? "default printer"}!';
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'Print failed: ${response.body}';
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Print error: $e';
      });
    }
  }

  // ==================== Save Settings ====================

  void _savePageSettings() {
    // Update global print settings
    int paperMm = _paperSize == '58mm' ? 58 : (_paperSize == '80mm' ? 80 : 210);
    globalPrintSettings.update(
      paperWidthMm: paperMm,
      receiptCharWidth: _charWidth,
      fontSizePt: _fontSize,
      paperSize: _paperSize == 'A4' ? PaperSize.a4 : PaperSize.receipt,
    );
    setState(() => _success = 'Page settings saved!');
  }

  Future<void> _saveToCloud() async {
    if (_repo == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _repo!.save(CloudPrinterSettings(
        enabled: false,  // No cloud printing
        useLocalBackend: true,  // Always use local backend
        localBackendUrl: _backendUrlCtrl.text.trim(),
      ));

      setState(() {
        _loading = false;
        _success = 'Settings saved!';
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeId = ref.watch(selectedStoreIdProvider);
    
    if (storeId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Printer Settings')),
        body: const Center(child: Text('Please select a store first')),
      );
    }

    _repo ??= CloudPrinterSettingsRepository(storeId: storeId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Printer Settings'),
        actions: [
          if (_loading)
            Padding(
              padding: context.padLg,
              child: const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              tooltip: 'Save Settings',
              onPressed: () {
                _savePageSettings();
                _saveToCloud();
              },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: context.padLg,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==================== LOCAL BACKEND STATUS ====================
            // Connection Status Card
            Card(
              color: _localBackendAvailable 
                  ? context.appColors.success.withOpacity(0.1) 
                  : context.appColors.warning.withOpacity(0.1),
              child: Padding(
                padding: context.padLg,
                child: Row(
                  children: [
                    Icon(
                      _localBackendAvailable ? Icons.check_circle : Icons.wifi_find,
                      color: _localBackendAvailable ? context.appColors.success : context.appColors.warning,
                      size: 32,
                    ),
                    context.gapHLg,
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _localBackendAvailable ? 'Printer Service Connected' : 'Connecting to Printer Service...',
                              style: context.texts.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: _localBackendAvailable ? context.appColors.success : context.appColors.warning,
                              ),
                            ),
                            context.gapVXs,
                            Text(
                              _backendUrlCtrl.text,
                              style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      if (_testingLocal)
                        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      else
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _testLocalBackend,
                          tooltip: 'Retry Connection',
                        ),
                    ],
                  ),
                ),
              ),
              
              // Setup instructions (only if not connected)
              if (!_localBackendAvailable) ...[
                context.gapVLg,
                Card(
                  color: context.colors.surfaceContainerHighest,
                  child: Padding(
                    padding: context.padLg,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Quick Setup:', style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        context.gapVSm,
                        _buildStep('1', 'Connect printer to computer via USB'),
                        _buildStep('2', 'Run printer service on that computer:'),
                        context.gapVSm,
                        _buildCommandBox('cd printer_backend && npm start'),
                        context.gapVSm,
                        _buildStep('3', 'Use app on same WiFi network'),
                      ],
                    ),
                  ),
                ),
              ],
              
              // Action buttons
              if (_localBackendAvailable) ...[
                context.gapVMd,
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _loadingPrinters ? null : _loadLocalPrinters,
                      icon: _loadingPrinters
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                      label: const Text('Refresh Printers'),
                    ),
                    context.gapHMd,
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _testPrint,
                      icon: const Icon(Icons.print),
                      label: const Text('Test Print'),
                    ),
                  ],
                ),
              ],
              
              // ==================== PRINTER LIST ====================
              context.gapVXl,
              Row(
                children: [
                  Icon(Icons.print, color: context.colors.primary),
                  context.gapHSm,
                  Text('Available Printers', style: context.texts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_localPrinters.isNotEmpty)
                    Text('${_localPrinters.length} found', style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
                ],
              ),
              context.gapVMd,
              
              if (_loadingPrinters)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Scanning for printers...'),
                      ],
                    ),
                  ),
                )
              else if (!_localBackendAvailable)
                Card(
                  color: context.appColors.warning.withOpacity(0.1),
                  child: Padding(
                    padding: context.padLg,
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: context.appColors.warning),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('Connect to printer service to see available printers')),
                      ],
                    ),
                  ),
                )
              else if (_localPrinters.isEmpty)
                Card(
                  color: context.colors.surfaceContainerHighest,
                  child: Padding(
                    padding: context.padLg,
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: context.colors.onSurfaceVariant),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('No printers found. Make sure a printer is connected and installed.')),
                      ],
                    ),
                  ),
                )
              else
                // Show grouped printer list
                ..._buildPrinterList(context),
              
              context.gapVXl,

            // ==================== PAGE SIZE SETTINGS ====================
            Text('Page & Format Settings', style: context.texts.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            context.gapVMd,
            
            Card(
              child: Padding(
                padding: context.padLg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Paper Size
                    Text('Paper Size', style: context.texts.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    context.gapVSm,
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: '58mm', label: Text('58mm'), icon: Icon(Icons.receipt)),
                        ButtonSegment(value: '80mm', label: Text('80mm'), icon: Icon(Icons.receipt_long)),
                        ButtonSegment(value: 'A4', label: Text('A4'), icon: Icon(Icons.description)),
                      ],
                      selected: {_paperSize},
                      onSelectionChanged: (Set<String> selection) {
                        setState(() {
                          _paperSize = selection.first;
                          // Auto-adjust char width based on paper
                          if (_paperSize == '58mm') {
                            _charWidth = 32;
                          } else if (_paperSize == '80mm') {
                            _charWidth = 48;
                          } else {
                            _charWidth = 80;
                          }
                        });
                      },
                    ),
                    
                    context.gapVLg,
                    
                    // Character Width
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Characters per Line: $_charWidth'),
                              Slider(
                                value: _charWidth.toDouble(),
                                min: 20,
                                max: 80,
                                divisions: 60,
                                label: '$_charWidth',
                                onChanged: (v) => setState(() => _charWidth = v.round()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    context.gapVSm,
                    
                    // Font Size
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Font Size: ${_fontSize}pt'),
                              Slider(
                                value: _fontSize.toDouble(),
                                min: 6,
                                max: 14,
                                divisions: 8,
                                label: '${_fontSize}pt',
                                onChanged: (v) => setState(() => _fontSize = v.round()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    
                    context.gapVLg,
                    
                    // Preview
                    Container(
                      width: double.infinity,
                      padding: context.padMd,
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        border: Border.all(color: context.colors.outlineVariant),
                        borderRadius: context.radiusXs,
                      ),
                      child: Text(
                        _generatePreview(),
                        style: TextStyle(
                          fontFamily: 'Courier',
                          fontSize: _fontSize.toDouble(),
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Error/Success messages
            if (_error != null) ...[
              context.gapVLg,
              _buildMessage(_error!, isError: true),
            ],
            if (_success != null) ...[
              context.gapVLg,
              _buildMessage(_success!, isError: false),
            ],
            
            context.gapVXl,
            
            // Help Section
            ExpansionTile(
              title: const Text('Need Help?'),
              leading: const Icon(Icons.help_outline),
              children: [
                Padding(
                  padding: context.padLg,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHelpItem('USB not detected?', 
                        'Make sure printer_backend is running on the computer with the USB printer.'),
                      _buildHelpItem('WiFi printer not working?', 
                        'Ensure the printer is shared on the network and all devices are on same WiFi.'),
                      _buildHelpItem('Receipt looks wrong?', 
                        'Adjust the Characters per Line to match your paper width.'),
                      _buildHelpItem('Text too small/large?', 
                        'Use the Font Size slider to adjust.'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPrinterList(BuildContext context) {
    final widgets = <Widget>[];
    
    void addSection(String title, IconData icon, Color color, List<PrinterInfo> printers) {
      if (printers.isEmpty) return;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              context.gapHSm,
              Text(title, style: context.texts.labelMedium?.copyWith(color: color, fontWeight: FontWeight.bold)),
              context.gapHSm,
              Text('(${printers.length})', style: context.texts.bodySmall?.copyWith(color: context.colors.onSurfaceVariant)),
            ],
          ),
        ),
      );
      widgets.addAll(printers.map((p) => _buildPrinterCard(context, p)));
    }
    
    // Add thermal printers first (most relevant for POS)
    final thermalPrinters = _localPrinters.where((p) => p.printerType == PrinterType.thermal).toList();
    if (thermalPrinters.isNotEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: context.appColors.success.withOpacity(0.1),
              borderRadius: context.radiusSm,
              border: Border.all(color: context.appColors.success.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.receipt, size: 18, color: context.appColors.success),
                const SizedBox(width: 8),
                Text('Recommended for POS', 
                  style: context.texts.labelMedium?.copyWith(color: context.appColors.success, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );
      widgets.addAll(thermalPrinters.map((p) => _buildPrinterCard(context, p, highlight: true)));
      
      // Separator
      if (thermalPrinters.length < _localPrinters.length) {
        widgets.add(const Divider(height: 24));
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Other Printers', style: context.texts.labelMedium?.copyWith(color: context.colors.onSurfaceVariant)),
          ),
        );
      }
    }
    
    // Add non-thermal printers grouped by connection
    final nonThermal = _localPrinters.where((p) => p.printerType != PrinterType.thermal).toList();
    if (nonThermal.isNotEmpty) {
      addSection('USB Connected', Icons.usb, context.appColors.info, 
        nonThermal.where((p) => p.connectionType == PrinterConnectionType.usb).toList());
      addSection('WiFi / Wireless', Icons.wifi, context.appColors.success,
        nonThermal.where((p) => p.connectionType == PrinterConnectionType.wifi).toList());
      addSection('Network Shared', Icons.lan, context.appColors.warning,
        nonThermal.where((p) => p.connectionType == PrinterConnectionType.network).toList());
      addSection('Local', Icons.computer, context.colors.tertiary,
        nonThermal.where((p) => p.connectionType == PrinterConnectionType.local).toList());
      addSection('Virtual / PDF', Icons.picture_as_pdf, context.colors.onSurfaceVariant,
        nonThermal.where((p) => p.connectionType == PrinterConnectionType.virtual).toList());
      addSection('Other', Icons.print, context.colors.onSurfaceVariant,
        nonThermal.where((p) => p.connectionType == PrinterConnectionType.unknown).toList());
    }
    
    return widgets;
  }

  Widget _buildPrinterCard(BuildContext context, PrinterInfo printer, {bool highlight = false}) {
    final isSelected = printer.name == _selectedPrinter;
    return Card(
      color: isSelected 
          ? context.colors.primaryContainer 
          : highlight ? context.appColors.success.withOpacity(0.1) : null,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: () => _setDefaultPrinter(printer.name),
        borderRadius: context.radiusMd,
        child: Padding(
          padding: context.padMd,
          child: Row(
            children: [
              // Connection type icon
              Container(
                padding: context.padSm,
                decoration: BoxDecoration(
                  color: printer.connectionColor.withValues(alpha: 0.15),
                  borderRadius: context.radiusSm,
                ),
                child: Icon(printer.connectionIcon, color: printer.connectionColor, size: 24),
              ),
              context.gapHMd,
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
                            style: context.texts.titleSmall?.copyWith(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (printer.isDefault || isSelected)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.colors.primary,
                              borderRadius: context.radiusMd,
                            ),
                            child: Text(
                              'DEFAULT',
                              style: TextStyle(color: context.colors.onPrimary, fontSize: context.sizes.fontXs, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    context.gapVXs,
                    Row(
                      children: [
                        // Connection type badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: printer.connectionColor.withValues(alpha: 0.15),
                            borderRadius: context.radiusXs,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(printer.connectionIcon, size: 12, color: printer.connectionColor),
                              context.gapHXs,
                              Text(printer.connectionLabel, 
                                style: TextStyle(fontSize: context.sizes.fontSm, color: printer.connectionColor, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                        context.gapHSm,
                        // Printer type badge
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: context.colors.surfaceContainerHighest,
                            borderRadius: context.radiusXs,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(printer.typeIcon, size: 12, color: context.colors.onSurfaceVariant),
                              context.gapHXs,
                              Text(printer.typeLabel, 
                                style: TextStyle(fontSize: context.sizes.fontSm, color: context.colors.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        context.gapHSm,
                        // Status indicator with connected/not connected
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: printer.statusColor.withValues(alpha: 0.15),
                            borderRadius: context.radiusXs,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: printer.statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              context.gapHXs,
                              Text(
                                printer.connected ? printer.statusLabel : 'Not Connected',
                                style: TextStyle(fontSize: context.sizes.fontSm, color: printer.statusColor, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Select button
              if (!isSelected)
                TextButton(
                  onPressed: () => _setDefaultPrinter(printer.name),
                  child: const Text('Select'),
                )
              else
                Icon(Icons.check_circle, color: context.colors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 12,
            backgroundColor: context.colors.primary,
            child: Text(number, style: TextStyle(fontSize: context.sizes.fontSm, color: context.colors.onPrimary, fontWeight: FontWeight.bold)),
          ),
          context.gapHMd,
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildCommandBox(String command) {
    return Container(
      padding: context.padMd,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: context.radiusSm,
      ),
      child: Row(
        children: [
          const Icon(Icons.terminal, color: Colors.greenAccent, size: 18),
          context.gapHSm,
          Expanded(
            child: Text(
              command,
              style: TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: context.sizes.fontMd),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, color: Colors.white70, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: command));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied!')),
              );
            },
            tooltip: 'Copy',
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(String message, {required bool isError}) {
    return Card(
      color: isError ? context.colors.errorContainer : context.appColors.success.withOpacity(0.1),
      child: Padding(
        padding: context.padMd,
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: isError ? context.colors.error : context.appColors.success,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: isError ? context.colors.onErrorContainer : context.appColors.success),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() {
                if (isError) {
                  _error = null;
                } else {
                  _success = null;
                }
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpItem(String question, String answer) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: const TextStyle(fontWeight: FontWeight.bold)),
          context.gapVXs,
          Text(answer, style: TextStyle(color: context.colors.onSurfaceVariant)),
        ],
      ),
    );
  }

  String _generatePreview() {
    final w = _charWidth;
    String line([String ch = '-']) => ch * w;
    String center(String text) {
      if (text.length >= w) return text;
      final pad = (w - text.length) ~/ 2;
      return ' ' * pad + text;
    }
    
    return '''
${center('SAMPLE RECEIPT')}
${center('Store Name')}
${line()}
Date: 2025-11-29 12:00
Customer: Walk-in
${line()}
Item              Qty  Price
${line()}
Product A           2  ₹100
Product B           1   ₹75
${line()}
Subtotal:              ₹175
Tax:                     ₹0
${line('=')}
TOTAL:                 ₹175
${line()}
${center('Thank you!')}
''';
  }
}
