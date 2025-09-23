import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'inventory_repository.dart';

// Threshold constants
const int kLowStockThreshold = 5;
const Duration kSoonWindow = Duration(days: 7);
const Duration kWarnWindow = Duration(days: 30);

class ProductAlert {
  final ProductDoc product;
  final List<String> flags;
  final int totalQty;
  final DateTime? nearestExpiry;
  final int expiredCount;
  final int soonCount;
  final int warnCount;
  ProductAlert({
    required this.product,
    required this.flags,
    required this.totalQty,
    required this.nearestExpiry,
    required this.expiredCount,
    required this.soonCount,
    required this.warnCount,
  });
}

final _inventoryRepoProvider = Provider<InventoryRepository>((ref) => InventoryRepository());
final alertsProductsStreamProvider = StreamProvider.autoDispose<List<ProductDoc>>((ref) {
  final repo = ref.watch(_inventoryRepoProvider);
  return repo.streamProducts(tenantId: null); // show all
});

final alertsProvider = Provider.autoDispose<List<ProductAlert>>((ref) {
  final asyncProducts = ref.watch(alertsProductsStreamProvider).maybeWhen(data: (p) => p, orElse: () => <ProductDoc>[]);
  final now = DateTime.now();
  final soonCut = now.add(kSoonWindow);
  final warnCut = now.add(kWarnWindow);
  final list = <ProductAlert>[];
  for (final p in asyncProducts) {
    if (!p.isActive) continue;
    final total = p.totalStock;
    int expired = 0, soon = 0, warn = 0; DateTime? nearest;
    for (final b in p.batches) {
      final exp = b.expiry; if (exp == null) continue; if (nearest==null || exp.isBefore(nearest)) nearest = exp;
      if (exp.isBefore(now)) { expired++; }
      else if (!exp.isAfter(soonCut)) { soon++; }
      else if (!exp.isAfter(warnCut)) { warn++; }
    }
    final flags = <String>[];
    if (total <= kLowStockThreshold) flags.add('Low Stock');
    if (expired > 0) flags.add('Expired');
    if (soon > 0) flags.add('Expiring Soon');
    if (warn > 0 && soon == 0 && expired == 0) flags.add('Expiry Warning');
    if (flags.isEmpty) continue;
    list.add(ProductAlert(product: p, flags: flags, totalQty: total, nearestExpiry: nearest, expiredCount: expired, soonCount: soon, warnCount: warn));
  }
  list.sort((a,b){int score(ProductAlert x){int s=0; if(x.flags.contains('Expired')) s+=1000; if(x.flags.contains('Expiring Soon')) s+=500; if(x.flags.contains('Expiry Warning')) s+=200; if(x.flags.contains('Low Stock')) s+=100; return s - (x.nearestExpiry?.millisecondsSinceEpoch ?? 0);} return score(b).compareTo(score(a));});
  return list;
});

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});
  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  bool _showLowStock = true;
  bool _showExpired = true;
  bool _showSoon = true;
  bool _showWarn = true;

  List<ProductAlert> _applyFilters(List<ProductAlert> src) {
    return src.where((a) {
      bool include = false;
      for (final f in a.flags) {
        switch (f) {
          case 'Low Stock':
            if (_showLowStock) include = true;
            break;
          case 'Expired':
            if (_showExpired) include = true;
            break;
          case 'Expiring Soon':
            if (_showSoon) include = true;
            break;
          case 'Expiry Warning':
            if (_showWarn) include = true;
            break;
        }
        if (include) break;
      }
      return include;
    }).toList();
  }

  Color _flagColor(String flag) {
    switch (flag) {
      case 'Expired':
        return Colors.red.shade600;
      case 'Expiring Soon':
        return Colors.deepOrange.shade500;
      case 'Expiry Warning':
        return Colors.amber.shade700;
      case 'Low Stock':
        return Colors.purple.shade600;
      default:
        return Colors.grey;
    }
  }

  String _primarySeverity(List<String> flags) {
    if (flags.contains('Expired')) return 'Expired';
    if (flags.contains('Expiring Soon')) return 'Expiring Soon';
    if (flags.contains('Expiry Warning')) return 'Expiry Warning';
    if (flags.contains('Low Stock')) return 'Low Stock';
    return flags.isEmpty ? '' : flags.first;
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(alertsProductsStreamProvider);
    final allAlerts = ref.watch(alertsProvider);
    final filtered = _applyFilters(allAlerts);
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('Alerts', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 16),
          const Tooltip(
            message: 'Low Stock: totalQty <= 5\nExpiring Soon: expiry <= 7 days\nExpiry Warning: expiry <= 30 days\nExpired: expiry < today',
            child: Icon(Icons.info_outline, size: 18),
          ),
          const Spacer(),
          // Filter chips
          Wrap(spacing: 6, runSpacing: 4, children: [
            FilterChip(
              label: const Text('Low Stock'),
              selected: _showLowStock,
              onSelected: (v) => setState(() => _showLowStock = v),
              selectedColor: _flagColor('Low Stock').withOpacity(.15),
              checkmarkColor: _flagColor('Low Stock'),
              avatar: Icon(Icons.inventory_2, size: 16, color: _flagColor('Low Stock')),
            ),
            FilterChip(
              label: const Text('Expired'),
              selected: _showExpired,
              onSelected: (v) => setState(() => _showExpired = v),
              selectedColor: _flagColor('Expired').withOpacity(.15),
              checkmarkColor: _flagColor('Expired'),
              avatar: Icon(Icons.warning_amber_rounded, size: 16, color: _flagColor('Expired')),
            ),
            FilterChip(
              label: const Text('Expiring Soon'),
              selected: _showSoon,
              onSelected: (v) => setState(() => _showSoon = v),
              selectedColor: _flagColor('Expiring Soon').withOpacity(.15),
              checkmarkColor: _flagColor('Expiring Soon'),
              avatar: Icon(Icons.schedule, size: 16, color: _flagColor('Expiring Soon')),
            ),
            FilterChip(
              label: const Text('Expiry Warning'),
              selected: _showWarn,
              onSelected: (v) => setState(() => _showWarn = v),
              selectedColor: _flagColor('Expiry Warning').withOpacity(.15),
              checkmarkColor: _flagColor('Expiry Warning'),
              avatar: Icon(Icons.timelapse, size: 16, color: _flagColor('Expiry Warning')),
            ),
          ])
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: productsAsync.when(
            data: (_) {
              if (allAlerts.isEmpty) {
                return const Card(child: Center(child: Text('No alerts.')));
              }
              if (filtered.isEmpty) {
                return const Card(child: Center(child: Text('No alerts match filters.')));
              }
              return Card(
                child: LayoutBuilder(builder: (context, constraints) {
                  final table = DataTable(
                    columnSpacing: 28,
                    headingRowHeight: 42,
                    dataRowMinHeight: 40,
                    dataRowMaxHeight: 54,
                    columns: const [
                      DataColumn(label: Text('Severity')),
                      DataColumn(label: Text('SKU')),
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Flags')),
                      DataColumn(label: Text('Total Qty'), numeric: true),
                      DataColumn(label: Text('Nearest Expiry')),
                      DataColumn(label: Text('Expired'), numeric: true),
                      DataColumn(label: Text('Soon (<=7d)'), numeric: true),
                      DataColumn(label: Text('Warn (<=30d)'), numeric: true),
                    ],
                    rows: [
                      for (final a in filtered)
                        DataRow(cells: [
                          DataCell(_SeverityDot(severity: _primarySeverity(a.flags), color: _flagColor(_primarySeverity(a.flags)))),
                          DataCell(Text(a.product.sku)),
                          DataCell(Text(a.product.name)),
                          DataCell(Wrap(spacing: 4, runSpacing: -8, children: [
                            for (final f in a.flags)
                              Chip(
                                label: Text(f, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: _flagColor(f).withOpacity(.12),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                side: BorderSide(color: _flagColor(f).withOpacity(.5), width: .6),
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                          ])),
                          DataCell(Align(alignment: Alignment.centerRight, child: Text(a.totalQty.toString()))),
                          DataCell(Text(a.nearestExpiry == null ? '-' : _fmtDate(a.nearestExpiry!))),
                          DataCell(Align(alignment: Alignment.centerRight, child: Text(a.expiredCount.toString()))),
                          DataCell(Align(alignment: Alignment.centerRight, child: Text(a.soonCount.toString()))),
                          DataCell(Align(alignment: Alignment.centerRight, child: Text(a.warnCount.toString()))),
                        ])
                    ],
                  );
                  return SingleChildScrollView(
                    scrollDirection: Axis.vertical,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                        child: table,
                      ),
                    ),
                  );
                }),
              );
            },
            error: (e, st) => Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('Error: $e'))),
            loading: () => const Center(child: CircularProgressIndicator()),
          ),
        ),
      ]),
    );
  }
}

class _SeverityDot extends StatelessWidget {
  final String severity;
  final Color color;
  const _SeverityDot({required this.severity, required this.color});
  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(Icons.circle, size: 14, color: color),
      const SizedBox(width: 4),
      Flexible(child: Text(severity, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: color)))
    ]);
  }
}

String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
