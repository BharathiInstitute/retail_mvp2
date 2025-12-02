import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retail_mvp2/core/theme/theme_extension_helpers.dart';
import 'Products/inventory_repository.dart';
import '../stores/providers.dart';

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
  final storeId = ref.watch(selectedStoreIdProvider);
  if (storeId == null) return const Stream<List<ProductDoc>>.empty();
  return repo.streamProducts(storeId: storeId);
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
  // Horizontal scroll controller for mouse/touch drag gestures
  final ScrollController _hScrollCtrl = ScrollController();

  @override
  void dispose() {
    _hScrollCtrl.dispose();
    super.dispose();
  }

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
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    // Count by type
    final lowStockCount = allAlerts.where((a) => a.flags.contains('Low Stock')).length;
    final expiredCount = allAlerts.where((a) => a.flags.contains('Expired')).length;
    final soonCount = allAlerts.where((a) => a.flags.contains('Expiring Soon')).length;
    final warnCount = allAlerts.where((a) => a.flags.contains('Expiry Warning')).length;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.surface, cs.primaryContainer.withOpacity(0.05)],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 10 : 14),
        child: Column(
          children: [
            // Modern Header with Filter Chips
            Container(
              padding: EdgeInsets.all(isMobile ? sizes.gapSm : sizes.gapMd),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: context.radiusMd,
                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Column(
                children: [
                  // Stats row
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('Low Stock', lowStockCount, Icons.inventory_2_rounded, _flagColor(context, 'Low Stock'), _showLowStock, (v) => setState(() => _showLowStock = v)),
                        SizedBox(width: sizes.gapSm),
                        _buildFilterChip('Expired', expiredCount, Icons.error_rounded, _flagColor(context, 'Expired'), _showExpired, (v) => setState(() => _showExpired = v)),
                        SizedBox(width: sizes.gapSm),
                        _buildFilterChip('Soon', soonCount, Icons.schedule_rounded, _flagColor(context, 'Expiring Soon'), _showSoon, (v) => setState(() => _showSoon = v)),
                        SizedBox(width: sizes.gapSm),
                        _buildFilterChip('Warning', warnCount, Icons.timelapse_rounded, _flagColor(context, 'Expiry Warning'), _showWarn, (v) => setState(() => _showWarn = v)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: sizes.gapMd),
            // Content
            Expanded(
              child: productsAsync.when(
                data: (_) {
                  if (allAlerts.isEmpty) {
                    return _buildEmptyState(cs, 'No alerts', 'All products are in good condition');
                  }
                  if (filtered.isEmpty) {
                    return _buildEmptyState(cs, 'No alerts match filters', 'Try adjusting filters above');
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
                      child: isMobile ? _buildMobileList(filtered, cs) : _buildDesktopTable(filtered, cs),
                    ),
                  );
                },
                error: (e, st) => _buildEmptyState(cs, 'Error', e.toString()),
                loading: () => Center(child: CircularProgressIndicator(color: cs.primary)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, int count, IconData icon, Color color, bool selected, Function(bool) onSelected) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onSelected(!selected),
        borderRadius: context.radiusMd,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.12) : cs.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: context.radiusMd,
            border: Border.all(color: selected ? color.withOpacity(0.4) : cs.outlineVariant.withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: sizes.iconSm, color: selected ? color : cs.onSurfaceVariant),
              SizedBox(width: sizes.gapSm),
              Text(label, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: selected ? color : cs.onSurfaceVariant)),
              SizedBox(width: sizes.gapSm),
              Container(
                padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
                decoration: BoxDecoration(
                  color: selected ? color.withOpacity(0.2) : cs.outlineVariant.withOpacity(0.3),
                  borderRadius: context.radiusSm,
                ),
                child: Text(count.toString(), style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w700, color: selected ? color : cs.onSurfaceVariant)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs, String title, String subtitle) {
    return Builder(builder: (context) => Container(
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
              padding: context.padLg,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle_outline_rounded, size: 40, color: context.appColors.success.withOpacity(0.6)),
            ),
            const SizedBox(height: 14),
            Text(title, style: TextStyle(fontSize: context.sizes.fontMd, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
            context.gapVXs,
            Text(subtitle, style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant.withOpacity(0.7))),
          ],
        ),
      ),
    ));
  }

  Widget _buildMobileList(List<ProductAlert> filtered, ColorScheme cs) {
    return ListView.builder(
      padding: context.padSm,
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final a = filtered[index];
        return _buildMobileCard(a, cs);
      },
    );
  }

  Widget _buildMobileCard(ProductAlert a, ColorScheme cs) {
    final severity = _primarySeverity(a.flags);
    final color = _flagColor(context, severity);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 6)],
      ),
      child: Padding(
        padding: context.padMd,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: context.radiusSm,
                  ),
                  child: Icon(_severityIcon(severity), size: 14, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.product.name, style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface), overflow: TextOverflow.ellipsis),
                      Text(a.product.sku, style: TextStyle(fontSize: context.sizes.fontXs, color: cs.primary, fontFamily: 'monospace')),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: context.radiusSm,
                  ),
                  child: Text('Qty: ${a.totalQty}', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: a.flags.map((f) => _buildFlagChip(f)).toList(),
            ),
            if (a.nearestExpiry != null) ...[
              context.gapVSm,
              Row(
                children: [
                  Icon(Icons.event_rounded, size: 12, color: cs.onSurfaceVariant.withOpacity(0.6)),
                  context.gapHXs,
                  Text('Nearest: ${_fmtDate(a.nearestExpiry!)}', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant)),
                  const Spacer(),
                  if (a.expiredCount > 0) _buildCountBadge('Exp', a.expiredCount, cs.error),
                  if (a.soonCount > 0) _buildCountBadge('Soon', a.soonCount, context.appColors.warning),
                  if (a.warnCount > 0) _buildCountBadge('Warn', a.warnCount, context.appColors.warning),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFlagChip(String flag) {
    final color = _flagColor(context, flag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: context.radiusSm,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(flag, style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _buildCountBadge(String label, int count, Color color) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: context.radiusXs,
      ),
      child: Text('$label: $count', style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: color)),
    );
  }

  IconData _severityIcon(String severity) {
    switch (severity) {
      case 'Expired': return Icons.error_rounded;
      case 'Expiring Soon': return Icons.schedule_rounded;
      case 'Expiry Warning': return Icons.timelapse_rounded;
      case 'Low Stock': return Icons.inventory_2_rounded;
      default: return Icons.info_rounded;
    }
  }

  Widget _buildDesktopTable(List<ProductAlert> filtered, ColorScheme cs) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.5),
            border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
          ),
          child: Row(
            children: [
              SizedBox(width: 90, child: _headerText('Severity', cs)),
              SizedBox(width: 90, child: _headerText('SKU', cs)),
              Expanded(child: _headerText('Name', cs)),
              SizedBox(width: 140, child: _headerText('Flags', cs)),
              SizedBox(width: 50, child: _headerText('Qty', cs, center: true)),
              SizedBox(width: 90, child: _headerText('Expiry', cs)),
              SizedBox(width: 45, child: _headerText('Exp', cs, center: true)),
              SizedBox(width: 45, child: _headerText('Soon', cs, center: true)),
              SizedBox(width: 45, child: _headerText('Warn', cs, center: true)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final a = filtered[index];
              return _buildDesktopRow(a, cs, index);
            },
          ),
        ),
      ],
    );
  }

  Widget _headerText(String text, ColorScheme cs, {bool center = false}) {
    return Text(text, style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant), textAlign: center ? TextAlign.center : TextAlign.left);
  }

  Widget _buildDesktopRow(ProductAlert a, ColorScheme cs, int index) {
    final severity = _primarySeverity(a.flags);
    final color = _flagColor(context, severity);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: index.isEven ? cs.surface : cs.surfaceContainerHighest.withOpacity(0.25),
        borderRadius: context.radiusSm,
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Severity
            SizedBox(
              width: 90,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Flexible(child: Text(severity, style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: color), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ),
            // SKU
            SizedBox(
              width: 90,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withOpacity(0.08),
                  borderRadius: context.radiusXs,
                ),
                child: Text(a.product.sku, style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: cs.primary, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
              ),
            ),
            // Name
            Expanded(
              child: Text(a.product.name, style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface), overflow: TextOverflow.ellipsis),
            ),
            // Flags
            SizedBox(
              width: 140,
              child: Wrap(
                spacing: 4,
                runSpacing: 2,
                children: a.flags.map((f) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: _flagColor(context, f).withOpacity(0.1),
                    borderRadius: context.radiusXs,
                  ),
                  child: Text(f, style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w600, color: _flagColor(context, f))),
                )).toList(),
              ),
            ),
            // Qty
            SizedBox(
              width: 50,
              child: Text(a.totalQty.toString(), style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface), textAlign: TextAlign.center),
            ),
            // Expiry
            SizedBox(
              width: 90,
              child: Text(a.nearestExpiry == null ? '-' : _fmtDate(a.nearestExpiry!), style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant)),
            ),
            // Expired count
            SizedBox(
              width: 45,
              child: Text(a.expiredCount.toString(), style: TextStyle(fontSize: context.sizes.fontXs, color: a.expiredCount > 0 ? cs.error : cs.onSurfaceVariant, fontWeight: a.expiredCount > 0 ? FontWeight.w700 : FontWeight.normal), textAlign: TextAlign.center),
            ),
            // Soon count
            SizedBox(
              width: 45,
              child: Text(a.soonCount.toString(), style: TextStyle(fontSize: context.sizes.fontXs, color: a.soonCount > 0 ? context.appColors.warning : cs.onSurfaceVariant, fontWeight: a.soonCount > 0 ? FontWeight.w700 : FontWeight.normal), textAlign: TextAlign.center),
            ),
            // Warn count
            SizedBox(
              width: 45,
              child: Text(a.warnCount.toString(), style: TextStyle(fontSize: context.sizes.fontXs, color: a.warnCount > 0 ? context.appColors.warning : cs.onSurfaceVariant, fontWeight: a.warnCount > 0 ? FontWeight.w700 : FontWeight.normal), textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
