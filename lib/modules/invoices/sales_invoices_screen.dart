// Renamed from invoices.dart to sales_invoices.dart
// Content mirrors the original to avoid breakages.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:retail_mvp2/core/firestore_store_collections.dart';
import 'package:retail_mvp2/modules/stores/providers.dart';
import 'package:retail_mvp2/core/theme/theme_extension_helpers.dart';
import 'package:retail_mvp2/core/paging/infinite_scroll_controller.dart';
import 'package:retail_mvp2/core/firebase/firestore_pagination_helper.dart';
import 'package:retail_mvp2/core/loading/page_loading_state_widget.dart';

// Simple wrapper page used by router for Sales invoices
class SalesInvoicesScreen extends StatelessWidget {
  final EdgeInsetsGeometry contentPadding;
  final double searchLeftShift;
  const SalesInvoicesScreen({super.key, this.contentPadding = const EdgeInsets.all(12), this.searchLeftShift = 0});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: InvoicesListScreen(
        contentPadding: contentPadding,
        searchLeftShift: searchLeftShift,
      ),
    );
  }
}

class InvoicesListScreen extends ConsumerStatefulWidget {
  final String? invoiceId;
  final EdgeInsetsGeometry contentPadding;
  final double searchLeftShift;
  const InvoicesListScreen({super.key, this.invoiceId, this.contentPadding = const EdgeInsets.all(12), this.searchLeftShift = 0});

  @override
  ConsumerState<InvoicesListScreen> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends ConsumerState<InvoicesListScreen> {
  String query = '';
  String? statusFilter;
  DateTimeRange? dateRange;
  bool taxInclusive = true;
  // Vertical controller for infinite scroll
  final ScrollController _vScrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _vScrollCtrl.addListener(_maybeLoadMoreOnScroll);
  }

  @override
  void dispose() {
    _vScrollCtrl.removeListener(_maybeLoadMoreOnScroll);
    _vScrollCtrl.dispose();
    super.dispose();
  }

  void _maybeLoadMoreOnScroll() {
    if (!_vScrollCtrl.hasClients) return;
    if (_vScrollCtrl.position.extentAfter < 600) {
      final c = ref.read(salesInvoicesPagedControllerProvider);
      final s = c.state;
      if (!s.loading && !s.endReached) c.loadMore();
    }
  }

  List<Invoice> filteredInvoices(List<Invoice> source) {
    return source.where((inv) {
      final q = query.trim().toLowerCase();
      final matchesQuery = q.isEmpty || inv.invoiceNo.toLowerCase().contains(q) || inv.customer.name.toLowerCase().contains(q);
      final matchesStatus = statusFilter == null || inv.status == statusFilter;
      final matchesDate = dateRange == null || (inv.date.isAfter(dateRange!.start.subtract(const Duration(days: 1))) && inv.date.isBefore(dateRange!.end.add(const Duration(days: 1))));
      return matchesQuery && matchesStatus && matchesDate;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final paged = ref.watch(salesInvoicesPagedControllerProvider);
    final state = paged.state;
    final filtered = filteredInvoices(state.items);
    
    return PageLoaderOverlay(
      loading: state.loading && state.items.isEmpty,
      error: state.error,
      onRetry: () => ref.read(salesInvoicesPagedControllerProvider).resetAndLoad(),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.surface, cs.primaryContainer.withOpacity(0.03)],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 10 : 14),
          child: Column(
            children: [
              _buildModernSearchBar(cs, isMobile),
              context.gapVMd,
              Expanded(child: _buildModernInvoiceList(filtered, cs, isMobile)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernSearchBar(ColorScheme cs, bool isMobile) {
    final sizes = context.sizes;
    return Container(
      padding: EdgeInsets.all(isMobile ? sizes.gapSm : sizes.gapMd),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 10)],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Search field
            Container(
              width: isMobile ? 180 : 220,
              height: sizes.inputHeightSm,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: context.radiusSm,
                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
              ),
              child: TextField(
                style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurface),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded, size: sizes.iconSm, color: cs.onSurfaceVariant),
                  hintText: 'Search (invoice no / customer)',
                  hintStyle: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant.withOpacity(0.7)),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: sizes.gapSm),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => query = v),
              ),
            ),
            SizedBox(width: sizes.gapSm),
            // Status dropdown
            Container(
              height: sizes.inputHeightSm,
              padding: EdgeInsets.symmetric(horizontal: sizes.gapMd),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.4),
                borderRadius: context.radiusSm,
                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: statusFilter,
                  hint: Text('Status', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
                  style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface),
                  icon: Icon(Icons.keyboard_arrow_down_rounded, size: sizes.iconSm, color: cs.onSurfaceVariant),
                  items: const [
                    DropdownMenuItem(value: 'Paid', child: Text('Paid')),
                    DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                    DropdownMenuItem(value: 'Credit', child: Text('Credit')),
                  ],
                  onChanged: (v) => setState(() => statusFilter = v),
                ),
              ),
            ),
            context.gapHSm,
            // Date range
            _buildFilterBtn(
              icon: Icons.date_range_rounded,
              label: dateRange == null ? 'Date Range' : '${_fmtDate(dateRange!.start)} → ${_fmtDate(dateRange!.end)}',
              onTap: () async {
                final now = DateTime.now();
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(now.year - 1),
                  lastDate: DateTime(now.year + 1),
                );
                if (picked != null) setState(() => dateRange = picked);
              },
              cs: cs,
              active: dateRange != null,
            ),
            context.gapHSm,
            // Clear
            _buildFilterBtn(
              icon: Icons.clear_rounded,
              label: 'Clear',
              onTap: () => setState(() {
                query = '';
                statusFilter = null;
                dateRange = null;
              }),
              cs: cs,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBtn({required IconData icon, required String label, required VoidCallback onTap, required ColorScheme cs, bool active = false}) {
    final sizes = context.sizes;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radiusSm,
        child: Container(
          height: sizes.inputHeightSm,
          padding: EdgeInsets.symmetric(horizontal: sizes.gapMd),
          decoration: BoxDecoration(
            color: active ? cs.primary.withOpacity(0.1) : cs.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: context.radiusSm,
            border: Border.all(color: active ? cs.primary.withOpacity(0.3) : cs.outlineVariant.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: sizes.iconSm, color: active ? cs.primary : cs.onSurfaceVariant),
              SizedBox(width: sizes.gapXs),
              Text(label, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: active ? cs.primary : cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernInvoiceList(List<Invoice> list, ColorScheme cs, bool isMobile) {
    final sizes = context.sizes;
    if (list.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: context.radiusMd,
          border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(sizes.gapLg),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.receipt_long_rounded, size: sizes.iconXl, color: cs.primary.withOpacity(0.5)),
              ),
              SizedBox(height: sizes.gapMd),
              Text('No invoices found', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              SizedBox(height: sizes.gapXs),
              Text('Try adjusting your filters', style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurfaceVariant.withOpacity(0.7))),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 10)],
      ),
      child: ClipRRect(
        borderRadius: context.radiusMd,
        child: ListView.builder(
          controller: _vScrollCtrl,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final inv = list[i];
            return _buildModernInvoiceItem(inv, cs, isMobile, i);
          },
        ),
      ),
    );
  }

  Widget _buildModernInvoiceItem(Invoice inv, ColorScheme cs, bool isMobile, int index) {
    final sizes = context.sizes;
    final pm = (inv is InvoiceWithMode) ? inv.paymentMode : null;
    final statusColor = _getStatusColor(inv.status, cs);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showInvoiceDetails(inv),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? sizes.gapMd : sizes.gapMd, vertical: sizes.gapMd),
          decoration: BoxDecoration(
            color: index.isEven ? cs.surface : cs.surfaceContainerHighest.withOpacity(0.25),
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.2))),
          ),
          child: Row(
            children: [
              // Invoice icon
              Container(
                padding: EdgeInsets.all(sizes.gapSm),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: context.radiusSm,
                ),
                child: Icon(Icons.receipt_rounded, size: sizes.iconSm, color: cs.primary),
              ),
              SizedBox(width: sizes.gapMd),
              // Invoice details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invoice #${inv.invoiceNo} • ${inv.customer.name}',
                      style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: sizes.gapXs),
                    Row(
                      children: [
                        Text(
                          _fmtDate(inv.date),
                          style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant),
                        ),
                        Container(
                          margin: EdgeInsets.symmetric(horizontal: sizes.gapXs),
                          width: 3,
                          height: 3,
                          decoration: BoxDecoration(color: cs.outlineVariant, shape: BoxShape.circle),
                        ),
                        Text(
                          '₹${inv.total(taxInclusive: taxInclusive).toStringAsFixed(2)}',
                          style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.primary),
                        ),
                        if (pm != null && pm.isNotEmpty) ...[
                          Container(
                            margin: EdgeInsets.symmetric(horizontal: sizes.gapXs),
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(color: cs.outlineVariant, shape: BoxShape.circle),
                          ),
                          Text(pm, style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: context.radiusLg,
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Text(
                  inv.status,
                  style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: statusColor),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(String status, ColorScheme cs) {
    final app = context.appColors;
    if (status == 'Paid') return app.success;
    if (status == 'Pending') return app.warning;
    if (status == 'Credit') return app.info;
    return cs.outline;
  }

  Future<void> _showInvoiceDetails(Invoice inv) async {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    await showDialog(
      context: context,
      useRootNavigator: true,
      builder: (dialogCtx) {
        final size = MediaQuery.of(context).size;
        final isNarrow = size.width < 600;
        if (isNarrow) {
          return Dialog(
            insetPadding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            backgroundColor: cs.surface,
            child: SafeArea(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: StreamBuilder<Invoice>(
                  stream: _singleInvoiceStream(inv),
                  builder: (context, snap) {
                    final current = snap.data ?? inv;
                    return InvoiceDetailsContent(
                      invoice: current,
                      dialogCtx: dialogCtx,
                      taxInclusive: taxInclusive,
                      onDelete: (inv) => _deleteInvoice(inv, dialogCtx),
                    );
                  },
                ),
              ),
            ),
          );
        }
        return Dialog(
          insetPadding: EdgeInsets.all(sizes.gapMd),
          clipBehavior: Clip.antiAlias,
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(borderRadius: context.radiusLg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900, maxHeight: 680),
            child: StreamBuilder<Invoice>(
              stream: _singleInvoiceStream(inv),
              builder: (context, snap) {
                final current = snap.data ?? inv;
                return InvoiceDetailsContent(
                  invoice: current,
                  dialogCtx: dialogCtx,
                  taxInclusive: taxInclusive,
                  onDelete: (inv) => _deleteInvoice(inv, dialogCtx),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Stream<Invoice> _singleInvoiceStream(Invoice inv) {
    final selStore = ref.read(selectedStoreIdProvider);
    if (selStore == null) {
      return Stream<Invoice>.value(inv);
    }
    final col = StoreRefs.of(selStore).invoices();
    if (inv.docId != null) {
      return col.doc(inv.docId!).snapshots().where((d) => d.exists).map((d) {
        final data = d.data() as Map<String, dynamic>;
        return Invoice.fromFirestore(data, docId: d.id);
      });
    } else {
      return col.where('invoiceNumber', isEqualTo: inv.invoiceNo).limit(1).snapshots().map((qs) {
        if (qs.docs.isEmpty) return inv;
        final d = qs.docs.first;
        return Invoice.fromFirestore(d.data(), docId: d.id);
      });
    }
  }

  Future<void> _deleteInvoice(Invoice inv, BuildContext dialogCtx) async {
    try {
      final selStore = ref.read(selectedStoreIdProvider);
      if (selStore == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(dialogCtx).showSnackBar(const SnackBar(content: Text('Select a store first')));
        }
        return;
      }
      final col = StoreRefs.of(selStore).invoices();
      if (inv.docId != null) {
        await col.doc(inv.docId!).delete();
      } else {
        try {
          final q = await col.where('invoiceNumber', isEqualTo: inv.invoiceNo).limit(1).get();
          if (q.docs.isNotEmpty) {
            await q.docs.first.reference.delete();
          } else {
            await col.doc(inv.invoiceNo).delete();
          }
        } catch (_) {
          await col.doc(inv.invoiceNo).delete();
        }
      }
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(dialogCtx);
        messenger.showSnackBar(const SnackBar(content: Text('Invoice deleted')));
        ref.read(salesInvoicesPagedControllerProvider).resetAndLoad();
        if (Navigator.of(dialogCtx, rootNavigator: true).canPop()) {
          Navigator.of(dialogCtx, rootNavigator: true).pop();
        }
      }
    } catch (e) {
      if (context.mounted) {
        final messenger = ScaffoldMessenger.of(dialogCtx);
        messenger.showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }
}

class InvoiceDetailsContent extends StatefulWidget {
  final Invoice invoice;
  final BuildContext dialogCtx;
  final bool taxInclusive;
  final Future<void> Function(Invoice inv) onDelete;
  const InvoiceDetailsContent({super.key, required this.invoice, required this.dialogCtx, required this.taxInclusive, required this.onDelete});

  @override
  State<InvoiceDetailsContent> createState() => _InvoiceDetailsContentState();
}

class _InvoiceDetailsContentState extends State<InvoiceDetailsContent> {
  bool editing = false;
  final List<_SalesItemRow> rows = [];

  @override
  void initState() {
    super.initState();
    _loadFromInvoice(widget.invoice);
  }

  @override
  void didUpdateWidget(covariant InvoiceDetailsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!editing && (oldWidget.invoice != widget.invoice)) {
      rows.clear();
      _loadFromInvoice(widget.invoice);
      setState(() {});
    }
  }

  void _loadFromInvoice(Invoice inv) {
    for (final it in inv.items) {
      rows.add(_SalesItemRow(
        sku: it.product.sku,
        name: TextEditingController(text: it.product.name),
        qty: TextEditingController(text: it.qty.toString()),
        price: TextEditingController(text: it.product.price.toStringAsFixed(2)),
        taxPercent: it.product.taxPercent,
      ));
    }
    if (rows.isEmpty) {
      rows.add(_SalesItemRow(
        sku: '',
        name: TextEditingController(),
        qty: TextEditingController(text: '1'),
        price: TextEditingController(text: '0'),
        taxPercent: 0,
      ));
    }
  }

  @override
  void dispose() {
    for (final r in rows) { r.dispose(); }
    super.dispose();
  }

  double _toD(TextEditingController c) => double.tryParse(c.text.trim()) ?? 0.0;
  int _toI(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    final gst = inv.gstBreakup(taxInclusive: widget.taxInclusive);
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    final isNarrow = MediaQuery.of(context).size.width < 600;
    final statusColor = _getStatusColor(inv.status, cs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Modern header
        Container(
          padding: EdgeInsets.fromLTRB(isNarrow ? sizes.gapMd : sizes.gapMd, sizes.gapMd, sizes.gapSm, sizes.gapMd),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.3),
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(sizes.gapSm),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.1),
                  borderRadius: context.radiusMd,
                ),
                child: Icon(Icons.receipt_long_rounded, size: sizes.iconMd, color: cs.primary),
              ),
              SizedBox(width: sizes.gapMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invoice #${inv.invoiceNo}',
                      style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w700, color: cs.onSurface),
                    ),
                    SizedBox(height: sizes.gapXs / 2),
                    Text(
                      '${_fmtDate(inv.date)} • ${inv.customer.name}',
                      style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (!editing)
                _buildHeaderBtn(Icons.edit_rounded, 'Edit', () => setState(() => editing = true), cs.primary, cs)
              else ...[
                _buildHeaderBtn(Icons.close_rounded, 'Cancel', () => setState(() { editing = false; }), cs.onSurfaceVariant, cs),
                SizedBox(width: sizes.gapXs),
                _buildHeaderBtn(Icons.check_rounded, 'Save', _save, cs.primary, cs, filled: true),
              ],
              SizedBox(width: sizes.gapXs),
              _buildHeaderBtn(Icons.delete_outline_rounded, 'Delete', () => _confirmDelete(context), cs.error, cs),
              SizedBox(width: sizes.gapSm),
              Container(
                padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: context.radiusLg,
                  border: Border.all(color: statusColor.withOpacity(0.3)),
                ),
                child: Text(inv.status, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: statusColor)),
              ),
              SizedBox(width: sizes.gapXs),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(widget.dialogCtx, rootNavigator: true).pop(),
                icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isNarrow ? 12 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!editing)
                  _buildModernItemsTable(inv, cs, isNarrow)
                else
                  _buildEditableItems(cs, isNarrow),
                const SizedBox(height: 20),
                _buildModernSummary(gst, inv, cs, isNarrow),
              ],
            ),
          ),
        ),
        // Footer
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.3),
            border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(widget.dialogCtx, rootNavigator: true).pop(),
                child: Text('Close', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderBtn(IconData icon, String tooltip, VoidCallback onTap, Color color, ColorScheme cs, {bool filled = false}) {
    final sizes = context.sizes;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: context.radiusSm,
          child: Container(
            padding: EdgeInsets.all(sizes.gapSm),
            decoration: BoxDecoration(
              color: filled ? color.withOpacity(0.15) : Colors.transparent,
              borderRadius: context.radiusSm,
            ),
            child: Icon(icon, size: sizes.iconMd, color: color),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    final confirm = await showDialog<bool>(
      context: widget.dialogCtx,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: context.radiusMd),
        title: Text('Delete invoice?', style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w700, color: cs.onSurface)),
        content: Text(
          'This will permanently delete this sales invoice. This action cannot be undone.',
          style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurfaceVariant),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancel', style: TextStyle(color: cs.onSurfaceVariant))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) await widget.onDelete(widget.invoice);
  }

  Widget _buildModernItemsTable(Invoice inv, ColorScheme cs, bool isNarrow) {
    final sizes = context.sizes;
    if (isNarrow) {
      return Column(
        children: inv.items.map((it) => _buildMobileItemCard(it, cs)).toList(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            ),
            child: Row(
              children: [
                SizedBox(width: 100, child: Text('SKU', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))),
                Expanded(child: Text('Item', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant))),
                SizedBox(width: 50, child: Text('Qty', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant), textAlign: TextAlign.center)),
                SizedBox(width: 80, child: Text('Price', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant), textAlign: TextAlign.right)),
                SizedBox(width: 60, child: Text('GST %', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant), textAlign: TextAlign.center)),
                SizedBox(width: 90, child: Text('Line Total', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant), textAlign: TextAlign.right)),
              ],
            ),
          ),
          // Rows
          ...inv.items.asMap().entries.map((entry) {
            final index = entry.key;
            final it = entry.value;
            return Container(
              padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
              decoration: BoxDecoration(
                color: index.isEven ? cs.surface : cs.surfaceContainerHighest.withOpacity(0.25),
                border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: sizes.gapXs, vertical: sizes.gapXs / 2),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.08),
                        borderRadius: context.radiusSm,
                      ),
                      child: Text(it.product.sku, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.primary, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  Expanded(child: Text(it.product.name, style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface), overflow: TextOverflow.ellipsis)),
                  SizedBox(width: 50, child: Text(it.qty.toString(), style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface), textAlign: TextAlign.center)),
                  SizedBox(width: 80, child: Text('₹${it.product.price.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface), textAlign: TextAlign.right)),
                  SizedBox(width: 60, child: Text('${it.product.taxPercent}%', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant), textAlign: TextAlign.center)),
                  SizedBox(width: 90, child: Text('₹${it.lineTotal(taxInclusive: widget.taxInclusive).toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.primary), textAlign: TextAlign.right)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildMobileItemCard(InvoiceItem it, ColorScheme cs) {
    final sizes = context.sizes;
    return Container(
      margin: EdgeInsets.only(bottom: sizes.gapSm),
      padding: EdgeInsets.all(sizes.gapMd),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: sizes.gapXs, vertical: sizes.gapXs / 2),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.08),
                  borderRadius: context.radiusSm,
                ),
                child: Text(it.product.sku, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.primary, fontFamily: 'monospace')),
              ),
              SizedBox(width: sizes.gapSm),
              Expanded(child: Text(it.product.name, style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface), overflow: TextOverflow.ellipsis)),
            ],
          ),
          SizedBox(height: sizes.gapSm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Qty: ${it.qty}', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
              Text('₹${it.product.price.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
              Text('GST ${it.product.taxPercent}%', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
              Text('₹${it.lineTotal(taxInclusive: widget.taxInclusive).toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w700, color: cs.primary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEditableItems(ColorScheme cs, bool isNarrow) {
    final sizes = context.sizes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(sizes.gapXs),
              decoration: BoxDecoration(
                color: cs.primary.withOpacity(0.1),
                borderRadius: context.radiusSm,
              ),
              child: Icon(Icons.shopping_cart_rounded, size: sizes.iconXs, color: cs.primary),
            ),
            SizedBox(width: sizes.gapSm),
            Text('Items', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
            const Spacer(),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() {
                  rows.add(_SalesItemRow(
                    sku: '',
                    name: TextEditingController(),
                    qty: TextEditingController(text: '1'),
                    price: TextEditingController(text: '0'),
                    taxPercent: 0,
                  ));
                }),
                borderRadius: context.radiusSm,
                child: Container(
                  padding: EdgeInsets.all(sizes.gapXs),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.1),
                    borderRadius: context.radiusSm,
                  ),
                  child: Icon(Icons.add_rounded, size: sizes.iconMd, color: cs.primary),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: sizes.gapMd),
        for (int i = 0; i < rows.length; i++) _buildModernEditRow(i, cs, isNarrow),
      ],
    );
  }

  Widget _buildModernEditRow(int index, ColorScheme cs, bool isNarrow) {
    final sizes = context.sizes;
    final r = rows[index];
    
    if (isNarrow) {
      return Container(
        margin: EdgeInsets.only(bottom: sizes.gapMd),
        padding: EdgeInsets.all(sizes.gapMd),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.3),
          borderRadius: context.radiusMd,
          border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildCompactField(r.sku, 'SKU', (v) => r.sku = v, cs, isInitialValue: true)),
                SizedBox(width: sizes.gapSm),
                SizedBox(width: 70, child: _buildCompactFieldCtrl(r.qty, 'Qty', cs)),
                IconButton(
                  onPressed: rows.length <= 1 ? null : () => setState(() { rows.removeAt(index).dispose(); }),
                  icon: Icon(Icons.close_rounded, size: sizes.iconMd, color: cs.error.withOpacity(0.7)),
                ),
              ],
            ),
            SizedBox(height: sizes.gapSm),
            _buildCompactFieldCtrl(r.name, 'Item Name', cs),
            SizedBox(height: sizes.gapSm),
            Row(
              children: [
                Expanded(child: _buildCompactFieldCtrl(r.price, 'Unit Price ₹', cs)),
                SizedBox(width: sizes.gapSm),
                SizedBox(
                  width: 100,
                  child: _buildCompactDropdown(r.taxPercent, (v) => setState(() => r.taxPercent = v ?? r.taxPercent), cs),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: sizes.gapSm),
      padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: context.radiusMd,
      ),
      child: Row(
        children: [
          SizedBox(width: 100, child: _buildCompactField(r.sku, 'SKU', (v) => r.sku = v, cs, isInitialValue: true)),
          SizedBox(width: sizes.gapSm),
          Expanded(child: _buildCompactFieldCtrl(r.name, 'Item', cs)),
          SizedBox(width: sizes.gapSm),
          SizedBox(width: 60, child: _buildCompactFieldCtrl(r.qty, 'Qty', cs)),
          SizedBox(width: sizes.gapSm),
          SizedBox(width: 100, child: _buildCompactFieldCtrl(r.price, 'Price ₹', cs)),
          SizedBox(width: sizes.gapSm),
          SizedBox(width: 100, child: _buildCompactDropdown(r.taxPercent, (v) => setState(() => r.taxPercent = v ?? r.taxPercent), cs)),
          IconButton(
            onPressed: rows.length <= 1 ? null : () => setState(() { rows.removeAt(index).dispose(); }),
            icon: Icon(Icons.close_rounded, size: sizes.iconMd, color: cs.error.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactField(String initialValue, String label, ValueChanged<String> onChanged, ColorScheme cs, {bool isInitialValue = false}) {
    final sizes = context.sizes;
    return Container(
      height: sizes.inputHeightSm,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusSm,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: TextFormField(
        initialValue: isInitialValue ? initialValue : null,
        style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapSm),
          isDense: true,
        ),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildCompactFieldCtrl(TextEditingController ctrl, String label, ColorScheme cs) {
    final sizes = context.sizes;
    return Container(
      height: sizes.inputHeightSm,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusSm,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: TextFormField(
        controller: ctrl,
        style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapSm),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildCompactDropdown(int value, ValueChanged<int?> onChanged, ColorScheme cs) {
    final sizes = context.sizes;
    return Container(
      height: sizes.inputHeightSm,
      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusSm,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isExpanded: true,
          style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface),
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: sizes.iconSm, color: cs.onSurfaceVariant),
          items: const [0, 5, 12, 18, 28].map((v) => DropdownMenuItem(value: v, child: Text('Tax $v%'))).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildModernSummary(GSTBreakup gst, Invoice inv, ColorScheme cs, bool isNarrow) {
    final sizes = context.sizes;
    return Wrap(
      spacing: sizes.gapMd,
      runSpacing: sizes.gapMd,
      children: [
        // GST Breakup
        Container(
          padding: EdgeInsets.all(sizes.gapMd),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: context.radiusMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(sizes.gapXs),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.1),
                      borderRadius: context.radiusSm,
                    ),
                    child: Icon(Icons.receipt_rounded, size: sizes.iconXs, color: cs.primary),
                  ),
                  SizedBox(width: sizes.gapSm),
                  Text('GST Breakup', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
                ],
              ),
              SizedBox(height: sizes.gapSm),
              _buildSummaryRow('CGST', gst.cgst, cs),
              _buildSummaryRow('SGST', gst.sgst, cs),
              _buildSummaryRow('IGST', gst.igst, cs),
            ],
          ),
        ),
        // Totals
        Container(
          padding: EdgeInsets.all(sizes.gapMd),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: context.radiusMd,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(sizes.gapXs),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.1),
                      borderRadius: context.radiusSm,
                    ),
                    child: Icon(Icons.calculate_rounded, size: sizes.iconXs, color: cs.primary),
                  ),
                  SizedBox(width: sizes.gapSm),
                  Text('Totals', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
                ],
              ),
              SizedBox(height: sizes.gapSm),
              _buildSummaryRow('Tax Total', gst.totalTax, cs),
              Container(
                margin: EdgeInsets.symmetric(vertical: sizes.gapXs),
                height: 1,
                color: cs.outlineVariant.withOpacity(0.3),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Grand Total', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w700, color: cs.onSurface)),
                  Text('₹${inv.total(taxInclusive: widget.taxInclusive).toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontLg, fontWeight: FontWeight.w700, color: cs.primary)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, double value, ColorScheme cs) {
    final sizes = context.sizes;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: sizes.gapXs / 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
          SizedBox(width: sizes.gapLg),
          Text('₹${value.toStringAsFixed(2)}', style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: cs.onSurface)),
        ],
      ),
    );
  }

  Color _getStatusColor(String status, ColorScheme cs) {
    final app = context.appColors;
    if (status == 'Paid') return app.success;
    if (status == 'Pending') return app.warning;
    if (status == 'Credit') return app.info;
    return cs.outline;
  }

  Future<void> _save() async {
    final List<Map<String, dynamic>> lines = [];
    final Map<int, double> taxesByRate = {};
    double subtotal = 0, discountTotal = 0, taxTotal = 0, grandTotal = 0;
    for (final r in rows) {
      final name = r.name.text.trim();
      final qty = _toI(r.qty);
      final unitPrice = _toD(r.price);
      final taxPct = r.taxPercent;
      if (name.isEmpty || qty <= 0) continue;
      final base = unitPrice * qty;
      final discount = 0.0;
      final tax = (base - discount) * (taxPct / 100);
      final total = base - discount + tax;
      subtotal += base;
      discountTotal += discount;
      taxTotal += tax;
      grandTotal += total;
      taxesByRate.update(taxPct, (v) => v + tax, ifAbsent: () => tax);
      lines.add({
        'sku': r.sku,
        'name': name,
        'qty': qty,
        'unitPrice': unitPrice,
        'taxPercent': taxPct,
        'lineSubtotal': base,
        'discount': discount,
        'tax': tax,
        'lineTotal': total,
      });
    }
  final ref = await findInvoiceDocRef(context, widget.invoice.invoiceNo, docId: widget.invoice.docId);
    await ref.update({
      'lines': lines,
      'subtotal': subtotal,
      'discountTotal': discountTotal,
      'taxTotal': taxTotal,
      'grandTotal': grandTotal,
      'taxesByRate': taxesByRate.map((k, v) => MapEntry(k.toString(), v)),
      'updatedAt': DateTime.now().toIso8601String(),
    });
    if (mounted) setState(() => editing = false);
  }
}

class BillingCustomer {
  final String name;
  BillingCustomer({required this.name});
}

class BillingProduct {
  final String sku;
  final String name;
  final double price;
  final int taxPercent;
  BillingProduct({required this.sku, required this.name, required this.price, required this.taxPercent});
}

class InvoiceItem {
  final BillingProduct product;
  final int qty;
  InvoiceItem({required this.product, required this.qty});
  InvoiceItem copyWith({BillingProduct? product, int? qty}) =>
      InvoiceItem(product: product ?? this.product, qty: qty ?? this.qty);
  double lineSubtotal({required bool taxInclusive}) {
    if (taxInclusive) {
      final base = product.price / (1 + product.taxPercent / 100);
      return base * qty;
    } else {
      return product.price * qty;
    }
  }
  double lineTax({required bool taxInclusive}) {
    final base = lineSubtotal(taxInclusive: taxInclusive);
    return base * (product.taxPercent / 100);
  }
  double lineTotal({required bool taxInclusive}) {
    return lineSubtotal(taxInclusive: taxInclusive) + lineTax(taxInclusive: taxInclusive);
  }
}

class GSTBreakup {
  final double cgst;
  final double sgst;
  final double igst;
  const GSTBreakup({required this.cgst, required this.sgst, required this.igst});
  double get totalTax => cgst + sgst + igst;
}

class Invoice {
  final String invoiceNo;
  final BillingCustomer customer;
  final List<InvoiceItem> items;
  final DateTime date;
  final String status;
  final bool taxInclusive;
  final String? docId; // Firestore document ID

  Invoice({required this.invoiceNo, required this.customer, required this.items, required this.date, required this.status, required this.taxInclusive, this.docId});

  factory Invoice.fromFirestore(Map<String, dynamic> data, {String? docId}) {
    final invoiceNo = (data['invoiceNumber'] ?? data['invoiceNo'] ?? '').toString();
    final customerName = (data['customerName'] ?? 'Walk-in Customer').toString();
    final customer = BillingCustomer(name: customerName);
    DateTime date;
    if (data['timestampMs'] is int) {
      date = DateTime.fromMillisecondsSinceEpoch(data['timestampMs']);
    } else if (data['timestamp'] is String) {
      date = DateTime.tryParse(data['timestamp']) ?? DateTime.now();
    } else {
      date = DateTime.now();
    }
    final status = (data['status'] ?? 'Paid').toString();
    final linesRaw = data['lines'];
    final items = <InvoiceItem>[];
    if (linesRaw is List) {
      for (final l in linesRaw) {
        if (l is Map) {
          final sku = (l['sku'] ?? '').toString();
          final name = (l['name'] ?? '').toString();
          // Prefer POS schema fields; fallback to legacy and safe derivations
          double price = 0.0;
          if (l['price'] is num) {
            price = (l['price'] as num).toDouble();
          } else if (l['unitPrice'] is num) {
            price = (l['unitPrice'] as num).toDouble();
          } else {
            price = double.tryParse(l['price']?.toString() ?? '') ??
                    double.tryParse(l['unitPrice']?.toString() ?? '') ?? 0.0;
          }
          final qty = (l['qty'] is num) ? (l['qty'] as num).toInt() : int.tryParse(l['qty']?.toString() ?? '') ?? 1;
          // If unit price still zero, try deriving from lineSubtotal/qty
          if ((price == 0 || price.isNaN) && qty > 0) {
            final lineSubtotal = (l['lineSubtotal'] is num)
                ? (l['lineSubtotal'] as num).toDouble()
                : double.tryParse(l['lineSubtotal']?.toString() ?? '') ?? 0.0;
            if (lineSubtotal > 0) {
              price = lineSubtotal / qty;
            }
          }
          int tax = 0;
          if (l['taxPct'] is num) {
            tax = (l['taxPct'] as num).toInt();
          } else if (l['taxPercent'] is num) {
            tax = (l['taxPercent'] as num).toInt();
          } else {
            tax = int.tryParse(l['taxPct']?.toString() ?? '') ?? int.tryParse(l['taxPercent']?.toString() ?? '') ?? 0;
          }
          items.add(InvoiceItem(product: BillingProduct(sku: sku, name: name, price: price, taxPercent: tax), qty: qty));
        }
      }
    }
    final taxInclusive = data['taxInclusive'] == true;
    return Invoice(
      invoiceNo: invoiceNo,
      customer: customer,
      items: items,
      date: date,
      status: status,
      taxInclusive: taxInclusive,
      docId: docId,
    );
  }

  double subtotal({required bool taxInclusive}) => items.fold(0.0, (p, it) => p + it.lineSubtotal(taxInclusive: taxInclusive));
  double taxTotal({required bool taxInclusive}) => items.fold(0.0, (p, it) => p + it.lineTax(taxInclusive: taxInclusive));
  double total({required bool taxInclusive}) => items.fold(0.0, (p, it) => p + it.lineTotal(taxInclusive: taxInclusive));

  GSTBreakup gstBreakup({required bool taxInclusive}) {
    double cgst = 0, sgst = 0, igst = 0;
    for (final it in items) {
      final tax = it.lineTax(taxInclusive: taxInclusive);
      // Simple split 50/50 between CGST and SGST, IGST as 0 for local sales.
      cgst += tax / 2;
      sgst += tax / 2;
    }
    return GSTBreakup(cgst: cgst, sgst: sgst, igst: igst);
  }
}

class InvoiceWithMode extends Invoice {
  final String paymentMode;
  InvoiceWithMode({
    required super.invoiceNo,
    required super.customer,
    required super.items,
    required super.date,
    required super.status,
    required super.taxInclusive,
    super.docId,
    required this.paymentMode,
  });
}

// Edit dialog removed per request; inline Delete is available in details view.

class _SalesItemRow {
  String sku;
  final TextEditingController name;
  final TextEditingController qty;
  final TextEditingController price;
  int taxPercent;
  _SalesItemRow({required this.sku, required this.name, required this.qty, required this.price, required this.taxPercent});
  void dispose() { name.dispose(); qty.dispose(); price.dispose(); }
}

  Future<DocumentReference<Map<String, dynamic>>> findInvoiceDocRef(BuildContext ctx, String invoiceNo, {String? docId}) async {
  final selStore = ProviderScope.containerOf(ctx).read(selectedStoreIdProvider);
  if (selStore == null) {
    throw StateError('No store selected');
  }
  final col = StoreRefs.of(selStore).invoices();
  if (docId != null) return col.doc(docId);
  try {
    final q = await col.where('invoiceNumber', isEqualTo: invoiceNo).limit(1).get();
    if (q.docs.isNotEmpty) return q.docs.first.reference;
  } catch (_) {}
  return col.doc(invoiceNo);
}

String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}' ;

// Paged controller provider for Sales Invoices
final salesInvoicesPagedControllerProvider = ChangeNotifierProvider.autoDispose<PagedListController<Invoice>>((ref) {
  final selStore = ref.watch(selectedStoreIdProvider);
  final Query<Map<String, dynamic>>? base = (selStore == null)
      ? null
      : StoreRefs.of(selStore).invoices().orderBy('timestampMs', descending: true);

  final controller = PagedListController<Invoice>(
    pageSize: 100,
    loadPage: (cursor) async {
      if (base == null) return (<Invoice>[], null);
      final after = cursor as DocumentSnapshot<Map<String, dynamic>>?;
      final (items, next) = await fetchFirestorePage<Invoice>(
        base: base,
        after: after,
        pageSize: 100,
        map: (d) => Invoice.fromFirestore(d.data(), docId: d.id),
      );
      return (items, next);
    },
  );

  Future.microtask(controller.resetAndLoad);
  ref.onDispose(controller.dispose);
  return controller;
});
