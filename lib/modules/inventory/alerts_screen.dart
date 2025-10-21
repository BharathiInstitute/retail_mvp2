import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retail_mvp2/core/theme/theme_utils.dart';
import 'Products/inventory_repository.dart';

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

  Color _flagColor(BuildContext context, String flag) {
    final scheme = Theme.of(context).colorScheme;
    switch (flag) {
      case 'Expired':
        return scheme.error;
      case 'Expiring Soon':
        return context.appColors.warning;
      case 'Expiry Warning':
        return scheme.tertiary;
      case 'Low Stock':
        return context.appColors.info;
      default:
        return scheme.outline;
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
          Text('Alerts', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(width: 16),
          const Tooltip(
            message: 'Low Stock: totalQty <= 5\nExpiring Soon: expiry <= 7 days\nExpiry Warning: expiry <= 30 days\nExpired: expiry < today',
            child: Icon(Icons.info_outline, size: 18),
          ),
          const Spacer(),
          // Filter chips
          Wrap(spacing: 6, runSpacing: 4, children: [
            FilterChip(
              label: Text('Low Stock', style: context.texts.labelSmall?.copyWith(color: context.colors.onSurface)),
              selected: _showLowStock,
              onSelected: (v) => setState(() => _showLowStock = v),
              selectedColor: _flagColor(context, 'Low Stock').withValues(alpha: 0.15),
              checkmarkColor: _flagColor(context, 'Low Stock'),
              avatar: Icon(Icons.inventory_2, size: 16, color: _flagColor(context, 'Low Stock')),
            ),
            FilterChip(
              label: Text('Expired', style: context.texts.labelSmall?.copyWith(color: context.colors.onSurface)),
              selected: _showExpired,
              onSelected: (v) => setState(() => _showExpired = v),
              selectedColor: _flagColor(context, 'Expired').withValues(alpha: 0.15),
              checkmarkColor: _flagColor(context, 'Expired'),
              avatar: Icon(Icons.warning_amber_rounded, size: 16, color: _flagColor(context, 'Expired')),
            ),
            FilterChip(
              label: Text('Expiring Soon', style: context.texts.labelSmall?.copyWith(color: context.colors.onSurface)),
              selected: _showSoon,
              onSelected: (v) => setState(() => _showSoon = v),
              selectedColor: _flagColor(context, 'Expiring Soon').withValues(alpha: 0.15),
              checkmarkColor: _flagColor(context, 'Expiring Soon'),
              avatar: Icon(Icons.schedule, size: 16, color: _flagColor(context, 'Expiring Soon')),
            ),
            FilterChip(
              label: Text('Expiry Warning', style: context.texts.labelSmall?.copyWith(color: context.colors.onSurface)),
              selected: _showWarn,
              onSelected: (v) => setState(() => _showWarn = v),
              selectedColor: _flagColor(context, 'Expiry Warning').withValues(alpha: 0.15),
              checkmarkColor: _flagColor(context, 'Expiry Warning'),
              avatar: Icon(Icons.timelapse, size: 16, color: _flagColor(context, 'Expiry Warning')),
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
                          DataCell(_SeverityDot(severity: _primarySeverity(a.flags), color: _flagColor(context, _primarySeverity(a.flags)))),
                          DataCell(Text(a.product.sku)),
                          DataCell(Text(a.product.name)),
                          DataCell(Wrap(spacing: 4, runSpacing: -8, children: [
                            for (final f in a.flags)
                              Chip(
                                label: Text(
                                  f,
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        fontWeight: FontWeight.w500,
                                        color: Theme.of(context).colorScheme.onSurface,
                                      ),
                                ),
                                visualDensity: VisualDensity.compact,
                                backgroundColor: _flagColor(context, f).withValues(alpha: 0.12),
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                side: BorderSide(color: _flagColor(context, f).withValues(alpha: 0.5), width: .6),
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
                        child: DataTableTheme(
                          data: DataTableThemeData(
                            dataTextStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurface),
                            headingTextStyle: context.texts.bodySmall?.copyWith(color: context.colors.onSurface, fontWeight: FontWeight.w700),
                          ),
                          child: table,
                        ),
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
      Flexible(child: Text(severity, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)))
    ]);
  }
}

String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
