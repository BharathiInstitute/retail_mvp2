import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:retail_mvp2/modules/pos/pos_invoices/pdf_theme.dart' as app_pdf;
import 'package:barcode/barcode.dart';
import '../../../core/theme/theme_extension_helpers.dart';
import 'inventory_repository.dart';
import '../download_helper_stub.dart' if (dart.library.html) '../download_helper_web.dart';

// Label size: 2 inch × 1 inch = 50.8mm × 25.4mm
const double _labelWidthMm = 50.8;
const double _labelHeightMm = 25.4;
const double _labelWidthPt = _labelWidthMm * PdfPageFormat.mm;
const double _labelHeightPt = _labelHeightMm * PdfPageFormat.mm;

/// Custom page format for 2"×1" labels
final _labelFormat = PdfPageFormat(_labelWidthPt, _labelHeightPt, marginAll: 2 * PdfPageFormat.mm);

/// Builds a PDF containing barcodes - SINGLE COLUMN layout
/// Each label is 2 inch × 1 inch, one per row for easy printing
Future<Uint8List> buildBarcodesPdf(List<BarcodeProduct> products) async {
  final doc = pw.Document();
  final code128 = Barcode.code128();
  
  // Expand products by quantity
  final expandedItems = <BarcodeProduct>[];
  for (final p in products) {
    for (var i = 0; i < p.quantity; i++) {
      expandedItems.add(p);
    }
  }
  
  // Single column layout - one label per row on A4
  const pageHeight = 297.0; // A4 height in mm
  const marginMm = 10.0;
  
  final rowsPerPage = ((pageHeight - 2 * marginMm) / _labelHeightMm).floor();

  for (var pageStart = 0; pageStart < expandedItems.length; pageStart += rowsPerPage) {
    final pageItems = expandedItems.sublist(
      pageStart, 
      (pageStart + rowsPerPage).clamp(0, expandedItems.length),
    );
    
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(marginMm * PdfPageFormat.mm),
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: pageItems.map((p) => _buildGridLabel(p, code128)).toList(),
          );
        },
      ),
    );
  }

  return Uint8List.fromList(await doc.save());
}

/// Builds PDF for direct label printing - one label per page
Future<Uint8List> buildLabelsPdf(List<BarcodeProduct> products) async {
  final doc = pw.Document();
  final code128 = Barcode.code128();
  
  // Expand products by quantity
  final expandedItems = <BarcodeProduct>[];
  for (final p in products) {
    for (var i = 0; i < p.quantity; i++) {
      expandedItems.add(p);
    }
  }
  
  // One label per page - for direct label printing
  for (final item in expandedItems) {
    doc.addPage(
      pw.Page(
        pageFormat: _labelFormat,
        margin: pw.EdgeInsets.zero,
        build: (ctx) => _buildSingleLabel(item, code128),
      ),
    );
  }

  return Uint8List.fromList(await doc.save());
}

/// Build a single label for direct label printing (2"×1")
pw.Widget _buildSingleLabel(BarcodeProduct p, Barcode code128) {
  final data = p.realBarcode.isNotEmpty ? p.realBarcode : p.sku;
  final svg = code128.toSvg(data, width: 100, height: 28, drawText: false);
  
  return pw.Container(
    width: _labelWidthPt,
    height: _labelHeightPt,
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          p.name.length > 18 ? '${p.name.substring(0, 18)}...' : p.name,
          style: app_pdf.PdfTheme.headerCell.copyWith(fontSize: 7),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 1),
        pw.SvgImage(svg: svg),
        pw.SizedBox(height: 1),
        pw.Text(data, style: app_pdf.PdfTheme.cell.copyWith(fontSize: 6)),
      ],
    ),
  );
}

/// Build a label for grid layout on A4 (2"×1")
pw.Widget _buildGridLabel(BarcodeProduct p, Barcode code128) {
  final data = p.realBarcode.isNotEmpty ? p.realBarcode : p.sku;
  final svg = code128.toSvg(data, width: 100, height: 28, drawText: false);
  
  return pw.Container(
    width: _labelWidthPt,
    height: _labelHeightPt,
    padding: const pw.EdgeInsets.all(2),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey300, width: 0.3),
    ),
    child: pw.Column(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text(
          p.name.length > 18 ? '${p.name.substring(0, 18)}...' : p.name,
          style: app_pdf.PdfTheme.headerCell.copyWith(fontSize: 7),
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 1),
        pw.SvgImage(svg: svg),
        pw.SizedBox(height: 1),
        pw.Text(data, style: app_pdf.PdfTheme.cell.copyWith(fontSize: 6)),
      ],
    ),
  );
}

class BarcodeProduct {
  final String sku;
  final String name;
  final String realBarcode;
  final double unitPrice;
  final int quantity;
  
  BarcodeProduct({
    required this.sku,
    required this.name,
    required this.realBarcode,
    this.unitPrice = 0,
    this.quantity = 1,
  });
}

// ----- Print Barcodes Dialog -----

class PrintBarcodesDialog extends StatefulWidget {
  final List<ProductDoc> products;
  const PrintBarcodesDialog({super.key, required this.products});

  @override
  State<PrintBarcodesDialog> createState() => _PrintBarcodesDialogState();
}

class _PrintBarcodesDialogState extends State<PrintBarcodesDialog> {
  final Map<String, int> _quantities = {}; // sku -> quantity
  final Map<String, bool> _selected = {}; // sku -> selected
  String _search = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ProductDoc> get _filtered {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return widget.products;
    return widget.products.where((p) =>
      p.sku.toLowerCase().contains(q) ||
      p.name.toLowerCase().contains(q) ||
      p.barcode.toLowerCase().contains(q)
    ).toList();
  }

  int get _totalLabels {
    int total = 0;
    for (final entry in _quantities.entries) {
      if (_selected[entry.key] == true && entry.value > 0) {
        total += entry.value;
      }
    }
    return total;
  }

  int get _selectedCount => _selected.values.where((v) => v).length;

  void _selectAll(bool select) {
    setState(() {
      for (final p in _filtered) {
        _selected[p.sku] = select;
        if (select && !_quantities.containsKey(p.sku)) {
          _quantities[p.sku] = 1;
        }
      }
    });
  }

  List<BarcodeProduct> _getSelectedProducts() {
    final result = <BarcodeProduct>[];
    for (final p in widget.products) {
      if (_selected[p.sku] == true) {
        final qty = _quantities[p.sku] ?? 1;
        if (qty > 0) {
          result.add(BarcodeProduct(
            sku: p.sku,
            name: p.name,
            realBarcode: p.barcode,
            unitPrice: p.unitPrice,
            quantity: qty,
          ));
        }
      }
    }
    return result;
  }

  /// Direct print using browser print dialog
  Future<void> _printDirect() async {
    final products = _getSelectedProducts();
    if (products.isEmpty) return;
    
    try {
      // Build PDF with single labels (2"×1" each) for label printer
      final bytes = await buildLabelsPdf(products);
      
      // Use Printing.layoutPdf which opens browser print dialog on web
      final printed = await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Barcode_Labels',
        format: _labelFormat,
        usePrinterSettings: true,
      );
      
      if (!mounted) return;
      if (printed) {
        Navigator.pop(context);
      }
    } catch (e) {
      // Fallback: download PDF if printing fails
      if (!mounted) return;
      final products = _getSelectedProducts();
      final bytes = await buildLabelsPdf(products);
      await downloadBytes(bytes, 'barcode_labels.pdf', 'application/pdf');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF downloaded. Please print manually.')),
      );
    }
  }

  Future<void> _generatePdf() async {
    final products = _getSelectedProducts();
    if (products.isEmpty) return;
    
    late final Uint8List bytes;
    try {
      // Build PDF with single column layout on A4
      bytes = await buildBarcodesPdf(products);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to build PDF: $e')));
      return;
    }
    
    final ok = await downloadBytes(bytes, 'product_barcodes.pdf', 'application/pdf');
    if (!mounted) return;
    
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Barcodes PDF downloaded')));
      Navigator.pop(context);
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(
            'Barcodes PDF generated',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
          ),
          content: DefaultTextStyle(
            style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
                .copyWith(color: Theme.of(context).colorScheme.onSurface),
            child: const Text('Automatic download failed. Try again or check browser settings.'),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    final filtered = _filtered;

    return AlertDialog(
      title: Row(
        children: [
          Text(
            'Print Barcodes',
            style: texts.titleMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (_selectedCount > 0)
            Chip(
              label: Text('$_selectedCount selected • $_totalLabels labels'),
              backgroundColor: scheme.primaryContainer,
            ),
        ],
      ),
      content: SizedBox(
        width: 700,
        height: 500,
        child: Column(
          children: [
            // Search and select all row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by SKU, name, or barcode...',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: context.radiusSm),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                context.gapHMd,
                TextButton.icon(
                  onPressed: () => _selectAll(true),
                  icon: const Icon(Icons.select_all),
                  label: const Text('Select All'),
                ),
                TextButton.icon(
                  onPressed: () => _selectAll(false),
                  icon: const Icon(Icons.deselect),
                  label: const Text('Clear'),
                ),
              ],
            ),
            context.gapVMd,
            // Header row
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: context.radiusXs,
              ),
              child: Row(
                children: [
                  const SizedBox(width: 48), // checkbox space
                  Expanded(flex: 2, child: Text('Product', style: texts.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                  Expanded(flex: 1, child: Text('SKU', style: texts.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                  Expanded(flex: 1, child: Text('Price', style: texts.labelMedium?.copyWith(fontWeight: FontWeight.bold))),
                  SizedBox(width: 120, child: Text('Quantity', style: texts.labelMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                ],
              ),
            ),
            context.gapVXs,
            // List of products
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text('No products found', style: texts.bodyMedium))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final p = filtered[index];
                        final isSelected = _selected[p.sku] ?? false;
                        final qty = _quantities[p.sku] ?? 1;

                        return Container(
                          decoration: BoxDecoration(
                            color: isSelected ? scheme.primaryContainer.withOpacity(0.3) : null,
                            border: Border(bottom: BorderSide(color: scheme.outlineVariant, width: 0.5)),
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: isSelected,
                                onChanged: (v) {
                                  setState(() {
                                    _selected[p.sku] = v ?? false;
                                    if (v == true && !_quantities.containsKey(p.sku)) {
                                      _quantities[p.sku] = 1;
                                    }
                                  });
                                },
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  p.name,
                                  style: texts.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  p.sku,
                                  style: texts.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 1,
                                child: Text(
                                  '₹${p.unitPrice.toStringAsFixed(2)}',
                                  style: texts.bodySmall,
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                                      onPressed: isSelected && qty > 1
                                          ? () => setState(() => _quantities[p.sku] = qty - 1)
                                          : null,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32),
                                    ),
                                    SizedBox(
                                      width: 40,
                                      child: TextField(
                                        textAlign: TextAlign.center,
                                        decoration: const InputDecoration(
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                          border: OutlineInputBorder(),
                                        ),
                                        keyboardType: TextInputType.number,
                                        enabled: isSelected,
                                        controller: TextEditingController(text: qty.toString())
                                          ..selection = TextSelection.collapsed(offset: qty.toString().length),
                                        onChanged: (v) {
                                          final n = int.tryParse(v);
                                          if (n != null && n > 0) {
                                            setState(() => _quantities[p.sku] = n);
                                          }
                                        },
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.add_circle_outline, size: 20),
                                      onPressed: isSelected
                                          ? () => setState(() => _quantities[p.sku] = qty + 1)
                                          : null,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(minWidth: 32),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        OutlinedButton.icon(
          onPressed: _selectedCount > 0 ? _generatePdf : null,
          icon: const Icon(Icons.picture_as_pdf),
          label: Text('Download PDF ($_totalLabels)'),
        ),
        context.gapHSm,
        FilledButton.icon(
          onPressed: _selectedCount > 0 ? _printDirect : null,
          icon: const Icon(Icons.print),
          label: Text('Print ($_totalLabels labels)'),
        ),
      ],
    );
  }
}
