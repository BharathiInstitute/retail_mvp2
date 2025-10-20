import 'package:flutter/material.dart';
import 'package:pluto_grid/pluto_grid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth.dart';
import '../../../core/app_keys.dart';
import 'Products/inventory_repository.dart' show ProductDoc, InventoryRepository; // Product model type
import 'Products/inventory.dart' show inventoryRepoProvider, productsStreamProvider; // reuse providers from Products module

/// Spreadsheet-like inventory management using PlutoGrid.
/// Features:
/// - Excel-like inline editing (toggle edit mode)
/// - Add / Delete rows
/// - Auto-calculated Total = Quantity * Price
/// - Upload button to persist changes (create / update / delete)
/// NOTE: This example focuses on SKU uniqueness.
class InventorySheetPage extends ConsumerStatefulWidget {
  const InventorySheetPage({super.key});
  @override
  ConsumerState<InventorySheetPage> createState() => _InventorySheetPageState();
}

class _InventorySheetPageState extends ConsumerState<InventorySheetPage> {
  late List<PlutoColumn> columns;
  late PlutoGridStateManager? stateManager;
  bool _editingEnabled = true; // start editable
  bool _uploading = false;
  bool _fullscreen = false; // toggle to make grid full screen (edge-to-edge)
  void _fitColumns() {
    if (stateManager == null) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    final totalWidth = renderBox?.size.width ?? MediaQuery.of(context).size.width;
    final cols = stateManager!.columns;
    if (cols.isEmpty) return;
    final deleteCol = cols.where((c) => c.field == 'delete').toList();
    final adjustable = cols.where((c) => c.field != 'delete').toList();
    final reserved = (deleteCol.isNotEmpty ? deleteCol.first.width : 70) + 32; // delete col + padding
    final target = ((totalWidth - reserved) / adjustable.length).clamp(80, 5000);
    for (final col in adjustable) {
      stateManager!.resizeColumn(col, target - col.width);
    }
  }

  @override
  void initState() {
    super.initState();
    columns = [
      PlutoColumn(
        title: 'Item Name', field: 'name', type: PlutoColumnType.text(), enableEditingMode: true,
        renderer: (ctx) => Text(ctx.cell.value ?? ''),
      ),
      PlutoColumn(
        title: 'SKU', field: 'sku', type: PlutoColumnType.text(), enableEditingMode: true,
        frozen: PlutoColumnFrozen.start,
      ),
      PlutoColumn(
        title: 'Quantity', field: 'qty', type: PlutoColumnType.number(defaultValue: 0), enableEditingMode: true,
      ),
      PlutoColumn(
        title: 'Price', field: 'price', type: PlutoColumnType.number(defaultValue: 0), enableEditingMode: true,
      ),
      PlutoColumn(
        title: 'Total', field: 'total', type: PlutoColumnType.number(), enableEditingMode: false,
        renderer: (ctx){
          final row = ctx.row;
          final qty = (row.cells['qty']?.value ?? 0) as num;
          final price = (row.cells['price']?.value ?? 0) as num;
            final tot = qty * price;
          row.cells['total']!.value = tot;
          return Text(tot.toStringAsFixed(2));
        },
      ),
      PlutoColumn(
        title: 'Delete', field: 'delete', type: PlutoColumnType.text(), enableEditingMode: false,
        renderer: (ctx) {
          return IconButton(
            tooltip: 'Delete Row',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: !_editingEnabled ? null : () {
              stateManager?.removeRows([ctx.row]);
            },
          );
        },
        width: 70,
      ),
    ];
  }

  List<PlutoRow> _rowsFromProducts(List<ProductDoc> products) {
    return [
      for (final p in products)
        PlutoRow(cells: {
          'name': PlutoCell(value: p.name),
          'sku': PlutoCell(value: p.sku),
          'qty': PlutoCell(value: p.totalStock),
          'price': PlutoCell(value: p.unitPrice),
          'total': PlutoCell(value: p.totalStock * p.unitPrice),
          'delete': PlutoCell(value: ''),
        })
    ];
  }

  void _addEmptyRow() {
    final row = PlutoRow(cells: {
      'name': PlutoCell(value: ''),
      'sku': PlutoCell(value: ''),
      'qty': PlutoCell(value: 0),
      'price': PlutoCell(value: 0),
      'total': PlutoCell(value: 0),
      'delete': PlutoCell(value: ''),
    });
    stateManager?.appendRows([row]);
  }

  // --- Change Planning & Progress -------------------------------------------------

  Future<bool> _confirmUploadPlan({
    required int creates,
    required int updates,
    required int adjusts,
    required int deletes,
    required int totalOps,
  }) async {
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return false;
    final result = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Confirm Upload'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Creates: $creates'),
            Text('Updates: $updates'),
            Text('Stock Adjustments: $adjusts'),
            Text('Deletes: $deletes'),
            const SizedBox(height: 12),
            Text('Total operations: $totalOps'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => rootNavigatorKey.currentState?.pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => rootNavigatorKey.currentState?.pop(true), child: const Text('Proceed')),
        ],
      ),
    );
    return result == true;
  }

  Future<int> _showProgressAndRunOps({
    required List<_CreateOp> creates,
    required List<_UpdateOp> updates,
    required List<_AdjustOp> adjusts,
    required List<String> deletes,
    required int totalOps,
    required InventoryRepository repo,
    required String tenantFallback,
    required String? updatedByEmail,
  }) async {
    int processed = 0;
    String phase = 'Starting';
    String? error;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return 0;
    late void Function(VoidCallback fn) setDialogState;
    await showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        Future.microtask(() async {
          try {
            void update(String p) { phase = p; setDialogState(() {}); }
            for (final c in creates) {
              update('Create ${c.sku}');
              await repo.addProduct(
                tenantId: tenantFallback,
                sku: c.sku,
                name: c.name,
                unitPrice: c.price,
                taxPct: null,
                barcode: '',
                description: null,
                variants: const [],
                mrpPrice: null,
                costPrice: null,
                isActive: true,
                storeQty: c.qty,
                warehouseQty: 0,
              );
              processed++; setDialogState(() {});
            }
            for (final u in updates) {
              update('Update ${u.sku}');
              await repo.updateProduct(
                sku: u.sku,
                name: u.name,
                unitPrice: u.price,
                taxPct: u.existing.taxPct,
                barcode: u.existing.barcode,
                description: u.existing.description,
                variants: u.existing.variants,
                mrpPrice: u.existing.mrpPrice,
                costPrice: u.existing.costPrice,
                isActive: u.existing.isActive,
              );
              processed++; setDialogState(() {});
            }
            for (final a in adjusts) {
              update('Adjust ${a.sku} (${a.diff > 0 ? '+' : ''}${a.diff})');
              await repo.applyStockMovement(
                sku: a.sku,
                location: 'Store',
                deltaQty: a.diff,
                type: a.diff > 0 ? 'Inbound' : 'Outbound',
                note: 'Sheet upload adjust',
                updatedBy: updatedByEmail,
              );
              processed++; setDialogState(() {});
            }
            for (final d in deletes) {
              update('Delete $d');
              await repo.deleteProduct(sku: d);
              processed++; setDialogState(() {});
            }
          } catch (e) {
            error = e.toString();
          } finally {
            await Future.delayed(const Duration(milliseconds: 200));
            final nav = rootNavigatorKey.currentState;
            if (nav != null && nav.canPop()) nav.pop();
          }
        });
        return StatefulBuilder(builder: (context, setStateDialog) {
          setDialogState = setStateDialog;
          final value = totalOps == 0 ? null : processed / totalOps;
          return AlertDialog(
            title: const Text('Uploading...'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(value: processed == totalOps ? 1 : value),
                  const SizedBox(height: 12),
                  Text('Phase: $phase'),
                  const SizedBox(height: 4),
                  Text('Processed $processed of $totalOps'),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text('Error: $error', style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          );
        });
      },
    );
    return processed;
  }

  Future<void> _uploadChanges() async {
    if (stateManager == null) return;
    final user = ref.read(authStateProvider);
    if (user == null) {
      scaffoldMessengerKey.currentState?.showSnackBar(const SnackBar(content: Text('Sign in required.')));
      return;
    }
    final rootMessenger = scaffoldMessengerKey.currentState;
    setState(() => _uploading = true);
    try {
      final productsSnapshot = await ref.read(productsStreamProvider.future);
      final existingBySku = { for (final p in productsSnapshot) p.sku : p };
      final rows = stateManager!.rows;

      final seenSku = <String>{};
      final creates = <_CreateOp>[];
      final updates = <_UpdateOp>[];
      final adjusts = <_AdjustOp>[];

      for (final row in rows) {
        final sku = (row.cells["sku"]!.value ?? '').toString().trim();
        final name = (row.cells["name"]!.value ?? '').toString().trim();
        final qty = (row.cells["qty"]!.value ?? 0) as num;
        final price = (row.cells["price"]!.value ?? 0) as num;
        if (sku.isEmpty || name.isEmpty) continue;
        if (!seenSku.add(sku)) continue;
        final existing = existingBySku[sku];
        if (existing == null) {
          creates.add(_CreateOp(sku: sku, name: name, qty: qty.toInt(), price: price.toDouble()));
        } else {
          if (existing.name != name || existing.unitPrice != price.toDouble()) {
            updates.add(_UpdateOp(sku: sku, name: name, price: price.toDouble(), existing: existing));
          }
          final diff = qty.toInt() - existing.totalStock;
          if (diff != 0) adjusts.add(_AdjustOp(sku: sku, diff: diff));
        }
      }
      final gridSkus = rows.map((r) => (r.cells['sku']!.value ?? '').toString().trim()).where((s) => s.isNotEmpty).toSet();
      final deletes = [ for (final sku in existingBySku.keys) if (!gridSkus.contains(sku)) sku ];

      final totalOps = creates.length + updates.length + adjusts.length + deletes.length;
      if (totalOps == 0) {
        rootMessenger?.showSnackBar(const SnackBar(content: Text('No changes to upload.')));
        return;
      }

      final proceed = await _confirmUploadPlan(
        creates: creates.length,
        updates: updates.length,
        adjusts: adjusts.length,
        deletes: deletes.length,
        totalOps: totalOps,
      );
      if (!proceed) return;

      final repo = ref.read(inventoryRepoProvider);
      final tenantFallback = existingBySku.values.isEmpty ? user.uid : existingBySku.values.first.tenantId;
      final processed = await _showProgressAndRunOps(
        creates: creates,
        updates: updates,
        adjusts: adjusts,
        deletes: deletes,
        totalOps: totalOps,
        repo: repo,
        tenantFallback: tenantFallback,
        updatedByEmail: user.email,
      );

      if (processed == totalOps) {
        rootMessenger?.showSnackBar(const SnackBar(content: Text('Upload complete')));
      } else {
        rootMessenger?.showSnackBar(SnackBar(content: Text('Upload incomplete ($processed/$totalOps). See log.')));
      }
    } catch (e) {
      rootMessenger?.showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsStreamProvider);
    final toolbar = Padding(
      padding: EdgeInsets.symmetric(horizontal: _fullscreen ? 4 : 8, vertical: _fullscreen ? 4 : 8),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: _editingEnabled ? _addEmptyRow : null,
            icon: const Icon(Icons.add),
            label: const Text('Add Row'),
          ),
          const SizedBox(width: 8),
            FilledButton.icon(
            onPressed: _editingEnabled ? () => stateManager?.removeCurrentRow() : null,
            icon: const Icon(Icons.remove_circle_outline),
            label: const Text('Delete Selected'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _editingEnabled = !_editingEnabled),
            icon: Icon(_editingEnabled ? Icons.lock_open : Icons.lock),
            label: Text(_editingEnabled ? 'Editing ON' : 'Editing OFF'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _uploading ? null : _uploadChanges,
            icon: _uploading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_upload_outlined),
            label: const Text('Upload Changes'),
          ),
          const Spacer(),
          Tooltip(
            message: _fullscreen ? 'Exit Full Screen' : 'Full Screen',
            child: IconButton(
              onPressed: () {
                setState(() => _fullscreen = !_fullscreen);
                WidgetsBinding.instance.addPostFrameCallback((_) => _fitColumns());
              },
              icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
            ),
          ),
        ],
      ),
    );

    final gridWidget = productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (products) {
        final initialRows = _rowsFromProducts(products);
        return PlutoGrid(
          columns: columns,
          rows: initialRows,
          onLoaded: (event) {
            stateManager = event.stateManager;
            stateManager!.setShowColumnFilter(true);
            stateManager!.setAutoEditing(true);
            stateManager!.setSelectingMode(PlutoGridSelectingMode.row);
            // Fit columns to take entire width initially
            WidgetsBinding.instance.addPostFrameCallback((_) => _fitColumns());
          },
          configuration: PlutoGridConfiguration(
            style: PlutoGridStyleConfig(
              columnHeight: 38,
              rowHeight: 36,
              gridBorderColor: Theme.of(context).dividerColor,
              gridBackgroundColor: Theme.of(context).colorScheme.surface,
            ),
            columnFilter: PlutoGridColumnFilterConfig(),
          ),
          onChanged: (c) {
            if (c.column.field == 'qty' || c.column.field == 'price') {
              final row = c.row;
              final qty = (row.cells['qty']?.value ?? 0) as num;
              final price = (row.cells['price']?.value ?? 0) as num;
              row.cells['total']!.value = qty * price;
              stateManager?.notifyListeners();
            }
          },
        );
      },
    );

    if (_fullscreen) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [toolbar, const Divider(height: 1), Expanded(child: gridWidget)],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory Sheet (PlutoGrid)'),
        actions: [
          IconButton(
            tooltip: _fullscreen ? 'Exit Full Screen' : 'Full Screen',
            onPressed: () {
              setState(() => _fullscreen = !_fullscreen);
              WidgetsBinding.instance.addPostFrameCallback((_) => _fitColumns());
            },
            icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
          ),
        ],
      ),
      body: Column(
        children: [toolbar, const Divider(height: 1), Expanded(child: gridWidget)],
      ),
    );
  }
}

// --- Internal operation planning models ----------------------------------------
class _CreateOp {
  final String sku;
  final String name;
  final int qty;
  final double price;
  _CreateOp({required this.sku, required this.name, required this.qty, required this.price});
}

class _UpdateOp {
  final String sku;
  final String name;
  final double price;
  final ProductDoc existing;
  _UpdateOp({required this.sku, required this.name, required this.price, required this.existing});
}

class _AdjustOp {
  final String sku;
  final int diff;
  _AdjustOp({required this.sku, required this.diff});
}
