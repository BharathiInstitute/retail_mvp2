import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_repository_and_provider.dart';
import '../../core/theme/theme_extension_helpers.dart';
import 'Products/inventory.dart' show productsStreamProvider, inventoryRepoProvider, selectedStoreProvider; // reuse existing providers
import 'Products/inventory_repository.dart'; // for ProductDoc
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:retail_mvp2/core/paging/infinite_scroll_controller.dart';
import 'package:retail_mvp2/core/firebase/firestore_pagination_helper.dart';
import 'package:retail_mvp2/core/loading/page_loading_state_widget.dart';
import 'package:retail_mvp2/core/firestore_store_collections.dart';

// Local + Firestore-integrated stock movements screen
class StockMovementsScreen extends ConsumerStatefulWidget {
  const StockMovementsScreen({super.key});
  @override
  ConsumerState<StockMovementsScreen> createState() => _StockMovementsScreenState();
}

// Using existing repository & products stream via inventory.dart exports.

class _StockMovementsScreenState extends ConsumerState<StockMovementsScreen> {
  String _filter = '';
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
    final extentAfter = _vScrollCtrl.position.extentAfter;
    if (extentAfter < 600) {
      final controller = ref.read(movementsPagedControllerProvider);
      final s = controller.state;
      if (!s.loading && !s.endReached) {
        controller.loadMore();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final paged = ref.watch(movementsPagedControllerProvider);
    final state = paged.state;
    final cs = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 900;
    
    // Calculate stats
    final items = state.items;
    final inboundCount = items.where((m) => m.type == 'Inbound').length;
    final outboundCount = items.where((m) => m.type == 'Outbound').length;
    final adjustCount = items.where((m) => m.type == 'Adjust').length;
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.surface,
            cs.primaryContainer.withOpacity(0.08),
            cs.secondaryContainer.withOpacity(0.05),
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 8 : 16),
        child: Column(children: [
          // Modern Glass-morphic Header
          Container(
            padding: EdgeInsets.all(isMobile ? 12 : 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cs.surface.withOpacity(0.9),
                  cs.surfaceContainerHighest.withOpacity(0.7),
                ],
              ),
              borderRadius: context.radiusLg,
              border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(color: cs.shadow.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4)),
                BoxShadow(color: cs.primary.withOpacity(0.03), blurRadius: 40, spreadRadius: -10),
              ],
            ),
            child: Column(
              children: [
                // Action row - responsive
                isMobile
                    ? Column(
                        children: [
                          // Add Button - full width on mobile
                          SizedBox(
                            width: double.infinity,
                            child: _buildAddButton(cs),
                          ),
                          context.gapVMd,
                          // Search Field
                          _buildSearchField(cs),
                        ],
                      )
                    : Row(children: [
                        _buildAddButton(cs),
                        context.gapHLg,
                        Expanded(child: _buildSearchField(cs)),
                      ]),
                context.gapVMd,
                // Stats Cards - wrap on mobile
                isMobile
                    ? Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          SizedBox(width: (screenWidth - 40) / 2, child: _buildStatCard('Total', items.length.toString(), Icons.receipt_long_rounded, cs.primary, cs, compact: true)),
                          SizedBox(width: (screenWidth - 40) / 2, child: _buildStatCard('Inbound', inboundCount.toString(), Icons.arrow_downward_rounded, context.appColors.success, cs, compact: true)),
                          SizedBox(width: (screenWidth - 40) / 2, child: _buildStatCard('Outbound', outboundCount.toString(), Icons.arrow_upward_rounded, cs.error, cs, compact: true)),
                          SizedBox(width: (screenWidth - 40) / 2, child: _buildStatCard('Adjust', adjustCount.toString(), Icons.tune_rounded, context.appColors.info, cs, compact: true)),
                        ],
                      )
                    : Row(
                        children: [
                          _buildStatCard('Total', items.length.toString(), Icons.receipt_long_rounded, cs.primary, cs),
                          context.gapHMd,
                          _buildStatCard('Inbound', inboundCount.toString(), Icons.arrow_downward_rounded, context.appColors.success, cs),
                          context.gapHMd,
                          _buildStatCard('Outbound', outboundCount.toString(), Icons.arrow_upward_rounded, cs.error, cs),
                          context.gapHMd,
                          _buildStatCard('Adjust', adjustCount.toString(), Icons.tune_rounded, context.appColors.info, cs),
                        ],
                      ),
              ],
            ),
          ),
          context.gapVMd,
          Expanded(
            child: PageLoaderOverlay(
              loading: state.loading && state.items.isEmpty,
              error: state.error,
              onRetry: () => ref.read(movementsPagedControllerProvider).resetAndLoad(),
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surface.withOpacity(0.9),
                  borderRadius: context.radiusLg,
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(color: cs.shadow.withOpacity(0.08), blurRadius: 20, offset: const Offset(0, 4)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: context.radiusLg,
                  child: _buildResponsiveContent(context, state.items.where(_matchesFilter).toList(), state, ref, isMobile, isTablet),
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildAddButton(ColorScheme cs) {
    return Builder(builder: (context) {
      final sizes = context.sizes;
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [cs.primary, cs.primary.withOpacity(0.8)],
          ),
          borderRadius: context.radiusMd,
          boxShadow: [
            BoxShadow(color: cs.primary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openAddMovement,
            borderRadius: context.radiusMd,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline, size: sizes.iconSm, color: cs.onPrimary),
                  SizedBox(width: sizes.gapSm),
                  Text('Add Movement', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onPrimary)),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildSearchField(ColorScheme cs) {
    return Builder(builder: (context) {
      final sizes = context.sizes;
      return Container(
        height: sizes.inputHeightMd,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.5),
          borderRadius: context.radiusMd,
          border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
        ),
        child: TextField(
          style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurface),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search_rounded, size: sizes.iconSm, color: cs.onSurfaceVariant),
            hintText: 'Filter Movements',
            hintStyle: TextStyle(fontSize: sizes.fontSm, color: cs.onSurfaceVariant.withOpacity(0.7)),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapMd),
          ),
          onChanged: (v) => setState(() => _filter = v),
        ),
      );
    });
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, ColorScheme cs, {bool compact = false}) {
    final sizes = context.sizes;
    return compact
        ? Container(
            padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapSm),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
              ),
              borderRadius: context.radiusMd,
              border: Border.all(color: color.withOpacity(0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: sizes.iconSm, color: color),
                SizedBox(width: sizes.gapSm),
                Text(value, style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.bold, color: color)),
                SizedBox(width: sizes.gapXs),
                Text(label, style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
              ],
            ),
          )
        : Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapMd),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
                ),
                borderRadius: context.radiusMd,
                border: Border.all(color: color.withOpacity(0.2)),
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(sizes.gapSm),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: context.radiusSm,
                    ),
                    child: Icon(icon, size: sizes.iconMd, color: color),
                  ),
                  SizedBox(width: sizes.gapMd),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value, style: TextStyle(fontSize: sizes.fontLg, fontWeight: FontWeight.bold, color: color)),
                        Text(label, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
  }

  Widget _buildResponsiveContent(BuildContext context, List<MovementRecord> rows, PageState<MovementRecord> state, WidgetRef ref, bool isMobile, bool isTablet) {
    if (isMobile) {
      return _buildMobileList(context, rows, state, ref);
    } else {
      return _buildModernTable(context, rows, state, ref, isTablet);
    }
  }

  Widget _buildMobileList(BuildContext context, List<MovementRecord> rows, PageState<MovementRecord> state, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    if (rows.isEmpty && !state.loading) {
      return _buildEmptyState(cs);
    }
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _vScrollCtrl,
            padding: context.padSm,
            itemCount: rows.length,
            itemBuilder: (context, index) => _buildMobileCard(context, rows[index], cs),
          ),
        ),
        if (!state.endReached) _buildLoadMoreButton(state, ref, cs),
      ],
    );
  }

  Widget _buildMobileCard(BuildContext context, MovementRecord m, ColorScheme cs) {
    final sizes = context.sizes;
    final isInbound = m.type == 'Inbound';
    final isOutbound = m.type == 'Outbound';
    final typeColor = isInbound ? context.appColors.success : (isOutbound ? cs.error : context.appColors.info);
    final typeIcon = isInbound ? Icons.arrow_downward_rounded : (isOutbound ? Icons.arrow_upward_rounded : Icons.tune_rounded);
    final locColor = m.location == 'Store' ? cs.tertiary : context.appColors.info;
    final locIcon = m.location == 'Store' ? Icons.store_rounded : Icons.warehouse_rounded;

    return Container(
      margin: EdgeInsets.only(bottom: sizes.gapSm),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
        boxShadow: [BoxShadow(color: cs.shadow.withOpacity(0.05), blurRadius: 8)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openEditMovement(m),
          onLongPress: () => _confirmDeleteMovement(m),
          borderRadius: context.radiusMd,
          child: Padding(
            padding: EdgeInsets.all(sizes.gapMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Name and Qty
                Row(
                  children: [
                    Expanded(
                      child: Text(m.name, style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w600, color: cs.onSurface), overflow: TextOverflow.ellipsis),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
                      decoration: BoxDecoration(
                        color: (m.deltaQty >= 0 ? context.appColors.success : cs.error).withOpacity(0.1),
                        borderRadius: context.radiusSm,
                      ),
                      child: Text(
                        m.deltaQty >= 0 ? '+${m.deltaQty}' : '${m.deltaQty}',
                        style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w800, color: m.deltaQty >= 0 ? context.appColors.success : cs.error),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: sizes.gapSm),
                // SKU row
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.1),
                        borderRadius: context.radiusSm,
                      ),
                      child: Text(m.sku, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.primary, fontFamily: 'monospace')),
                    ),
                    const Spacer(),
                    Icon(Icons.schedule_rounded, size: sizes.iconXs, color: cs.onSurfaceVariant.withOpacity(0.6)),
                    SizedBox(width: sizes.gapXs),
                    Text(_fmtDateTime(m.date), style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
                  ],
                ),
                SizedBox(height: sizes.gapSm),
                // Bottom row: Type, Location, Stock info
                Row(
                  children: [
                    // Type chip
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
                      decoration: BoxDecoration(
                        color: typeColor.withOpacity(0.1),
                        borderRadius: context.radiusSm,
                        border: Border.all(color: typeColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(typeIcon, size: sizes.iconXs, color: typeColor),
                          SizedBox(width: sizes.gapXs),
                          Text(m.type, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: typeColor)),
                        ],
                      ),
                    ),
                    SizedBox(width: sizes.gapSm),
                    // Location chip
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
                      decoration: BoxDecoration(
                        color: locColor.withOpacity(0.1),
                        borderRadius: context.radiusSm,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(locIcon, size: sizes.iconXs, color: locColor),
                          SizedBox(width: sizes.gapXs),
                          Text(m.location, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: locColor)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Stock after info
                    Text('S:${m.storeAfter ?? "-"} W:${m.warehouseAfter ?? "-"}', style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme cs) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: context.padXl,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.inventory_2_outlined, size: 48, color: cs.onSurfaceVariant.withOpacity(0.5)),
          ),
          context.gapVLg,
          Text('No movements recorded', style: TextStyle(fontSize: context.sizes.fontLg, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
          context.gapVSm,
          Text('Add your first stock movement', style: TextStyle(fontSize: context.sizes.fontMd, color: cs.onSurfaceVariant.withOpacity(0.7))),
        ],
      ),
    );
  }

  Widget _buildLoadMoreButton(PageState<MovementRecord> state, WidgetRef ref, ColorScheme cs) {
    final sizes = context.sizes;
    return Container(
      padding: EdgeInsets.symmetric(vertical: sizes.gapMd),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
      ),
      child: state.loading
          ? SizedBox(width: sizes.iconLg, height: sizes.iconLg, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
          : TextButton.icon(
              onPressed: () => ref.read(movementsPagedControllerProvider).loadMore(),
              icon: Icon(Icons.expand_more_rounded, size: sizes.iconMd, color: cs.primary),
              label: Text('Load more', style: TextStyle(fontSize: sizes.fontSm, fontWeight: FontWeight.w500, color: cs.primary)),
              style: TextButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: sizes.gapLg, vertical: sizes.gapMd),
                backgroundColor: cs.primary.withOpacity(0.08),
                shape: RoundedRectangleBorder(borderRadius: context.radiusMd),
              ),
            ),
    );
  }

  bool _matchesFilter(MovementRecord m) {
    final q = _filter.trim().toLowerCase();
    if (q.isEmpty) return true;
    return m.sku.toLowerCase().contains(q) ||
        m.name.toLowerCase().contains(q) ||
        (m.note?.toLowerCase().contains(q) ?? false) ||
        (m.updatedBy?.toLowerCase().contains(q) ?? false);
  }

  Widget _buildModernTable(BuildContext context, List<MovementRecord> rows, PageState<MovementRecord> state, WidgetRef ref, bool isTablet) {
    final cs = Theme.of(context).colorScheme;
    if (rows.isEmpty && !state.loading) {
      return _buildEmptyState(cs);
    }
    
    // Define consistent column widths
    const double dateW = 115;
    const double typeW = 90;
    const double skuW = 95;
    const double productW = 130;
    const double locW = 95;
    const double qtyW = 60;
    const double storeW = 55;
    const double whW = 55;
    const double totalW = 55;
    const double rowPadding = 24; // horizontal padding
    const double totalMinWidth = dateW + typeW + skuW + productW + locW + qtyW + storeW + whW + totalW + rowPadding;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        final useScroll = constraints.maxWidth < totalMinWidth;
        
        Widget buildHeader() {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(0.6),
              border: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.3))),
            ),
            child: Row(
              children: [
                SizedBox(width: dateW, child: _headerCell('Date', Icons.calendar_today_rounded, cs)),
                SizedBox(width: typeW, child: _headerCell('Type', Icons.category_rounded, cs)),
                SizedBox(width: skuW, child: _headerCell('SKU', Icons.qr_code_2_rounded, cs)),
                SizedBox(width: productW, child: _headerCell('Product', Icons.inventory_2_rounded, cs)),
                SizedBox(width: locW, child: _headerCell('Location', Icons.place_rounded, cs)),
                SizedBox(width: qtyW, child: _headerCell('Qty', Icons.swap_vert_rounded, cs, center: true)),
                SizedBox(width: storeW, child: _headerCell('Store', Icons.store_rounded, cs, center: true)),
                SizedBox(width: whW, child: _headerCell('WH', Icons.warehouse_rounded, cs, center: true)),
                SizedBox(width: totalW, child: _headerCell('Total', Icons.functions_rounded, cs, center: true)),
              ],
            ),
          );
        }
        
        Widget buildRow(MovementRecord m, int index) {
          return _buildMovementRow(context, m, cs, index, dateW, typeW, skuW, productW, locW, qtyW, storeW, whW, totalW);
        }
        
        if (useScroll) {
          return Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: totalMinWidth, child: buildHeader()),
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: totalMinWidth,
                    child: ListView.builder(
                      controller: _vScrollCtrl,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: rows.length,
                      itemBuilder: (context, index) => buildRow(rows[index], index),
                    ),
                  ),
                ),
              ),
              if (!state.endReached) _buildLoadMoreButton(state, ref, cs),
            ],
          );
        }
        
        return Column(
          children: [
            buildHeader(),
            Expanded(
              child: ListView.builder(
                controller: _vScrollCtrl,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: rows.length,
                itemBuilder: (context, index) => buildRow(rows[index], index),
              ),
            ),
            if (!state.endReached) _buildLoadMoreButton(state, ref, cs),
          ],
        );
      },
    );
  }

  Widget _headerCell(String label, IconData icon, ColorScheme cs, {bool center = false}) {
    return Row(
      mainAxisAlignment: center ? MainAxisAlignment.center : MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: cs.onSurfaceVariant.withOpacity(0.7)),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildMovementRow(BuildContext context, MovementRecord m, ColorScheme cs, int index, double dateW, double typeW, double skuW, double productW, double locW, double qtyW, double storeW, double whW, double totalW) {
    final sizes = context.sizes;
    final isInbound = m.type == 'Inbound';
    final isOutbound = m.type == 'Outbound';
    final typeColor = isInbound ? context.appColors.success : (isOutbound ? cs.error : context.appColors.info);
    final typeIcon = isInbound ? Icons.arrow_downward_rounded : (isOutbound ? Icons.arrow_upward_rounded : Icons.tune_rounded);
    final locColor = m.location == 'Store' ? cs.tertiary : context.appColors.info;
    final locIcon = m.location == 'Store' ? Icons.store_rounded : Icons.warehouse_rounded;
    
    return Container(
      margin: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
      decoration: BoxDecoration(
        color: index.isEven ? cs.surface : cs.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openEditMovement(m),
          onLongPress: () => _confirmDeleteMovement(m),
          borderRadius: context.radiusMd,
          hoverColor: cs.primary.withOpacity(0.04),
          splashColor: cs.primary.withOpacity(0.08),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapSm),
            child: Row(
              children: [
                // Date
                SizedBox(
                  width: dateW,
                  child: Text(
                    _fmtDateTime(m.date),
                    style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurface, fontWeight: FontWeight.w500),
                  ),
                ),
                // Type chip
                SizedBox(
                  width: typeW,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.12),
                      borderRadius: context.radiusSm,
                      border: Border.all(color: typeColor.withOpacity(0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(typeIcon, size: sizes.iconXs, color: typeColor),
                        SizedBox(width: sizes.gapXs),
                        Text(m.type, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: typeColor)),
                      ],
                    ),
                  ),
                ),
                // SKU
                SizedBox(
                  width: skuW,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: sizes.gapXs, vertical: sizes.gapXs),
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.08),
                      borderRadius: context.radiusSm,
                    ),
                    child: Text(
                      m.sku,
                      style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: cs.primary, fontFamily: 'monospace'),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                // Product Name
                SizedBox(
                  width: productW,
                  child: Text(
                    m.name,
                    style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: cs.onSurface),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Location chip
                SizedBox(
                  width: locW,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
                    decoration: BoxDecoration(
                      color: locColor.withOpacity(0.1),
                      borderRadius: context.radiusSm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(locIcon, size: sizes.iconXs, color: locColor),
                        SizedBox(width: sizes.gapXs),
                        Text(m.location, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w600, color: locColor)),
                      ],
                    ),
                  ),
                ),
                // Delta Qty
                SizedBox(
                  width: qtyW,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: sizes.gapXs, vertical: sizes.gapXs),
                    decoration: BoxDecoration(
                      color: (m.deltaQty >= 0 ? context.appColors.success : cs.error).withOpacity(0.1),
                      borderRadius: context.radiusSm,
                    ),
                    child: Text(
                      m.deltaQty >= 0 ? '+${m.deltaQty}' : '${m.deltaQty}',
                      style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w700, color: m.deltaQty >= 0 ? context.appColors.success : cs.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                // Store After
                SizedBox(
                  width: storeW,
                  child: Text(
                    m.storeAfter?.toString() ?? '-',
                    style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
                // WH After
                SizedBox(
                  width: whW,
                  child: Text(
                    m.warehouseAfter?.toString() ?? '-',
                    style: TextStyle(fontSize: sizes.fontXs, color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
                // Total
                SizedBox(
                  width: totalW,
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: sizes.gapXs, vertical: sizes.gapXs),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withOpacity(0.5),
                      borderRadius: context.radiusSm,
                    ),
                    child: Text(
                      m.totalAfter?.toString() ?? '-',
                      style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Future<void> _openAddMovement() async {
    final result = await showDialog<MovementRecord>(
      context: context,
      builder: (_) => const _MovementDialog(),
    );
    if (result == null) return;
    // Already persisted; Firestore stream will refresh. No local list management now.
  }

  Future<void> _openEditMovement(MovementRecord m) async {
    if (m.id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot edit: missing document id')));
      }
      return;
    }
    // Show same fields as Add dialog; SKU fixed (read-only).
    final formKey = GlobalKey<FormState>();
    String type = m.type;
    String location = m.location;
    final qtyCtrl = TextEditingController(text: m.deltaQty == 0
        ? '0'
        : (m.type == 'Outbound' ? (m.deltaQty.abs()).toString() : (m.type == 'Inbound' ? (m.deltaQty.abs()).toString() : m.deltaQty.toString())));
    final noteCtrl = TextEditingController(text: m.note ?? '');
    int parseDelta(String type, String text) {
      final raw = int.tryParse(text.trim()) ?? 0;
      if (type == 'Inbound') return raw.abs();
      if (type == 'Outbound') return -raw.abs();
      return raw; // Adjust
    }
    final user = ref.read(authStateProvider);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Edit Movement', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
        content: DefaultTextStyle(
          style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(color: Theme.of(context).colorScheme.onSurface),
          child: Form(
          key: formKey,
          child: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SKU: ${m.sku} • ${m.name}', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600)),
                context.gapVMd,
                Row(children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      // initialValue removed (unsupported)
                      items: const ['Inbound', 'Outbound', 'Adjust']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => type = v ?? type,
                      decoration: const InputDecoration(labelText: 'Type'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                  context.gapHMd,
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      // initialValue removed (unsupported)
                      items: const ['Store', 'Warehouse']
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => location = v ?? location,
                      decoration: const InputDecoration(labelText: 'Location'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                ]),
                context.gapVSm,
                TextFormField(
                  controller: qtyCtrl,
                  decoration: InputDecoration(
                    labelText: type == 'Adjust' ? 'Adjust Qty (can be +/-)' : 'Quantity',
                    helperText: type == 'Outbound' ? 'Will subtract this quantity' : (type == 'Inbound' ? 'Will add this quantity' : 'Positive or negative'),
                  ),
                  keyboardType: TextInputType.number,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    final n = int.tryParse(v.trim());
                    if (n == null) return 'Invalid';
                    if (type == 'Outbound' && n <= 0) return 'Enter positive number';
                    if (type != 'Outbound' && type != 'Adjust' && n < 0) return 'Cannot be negative';
                    return null;
                  },
                ),
                context.gapVSm,
                TextFormField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Note', hintText: 'Optional remarks'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(dialogCtx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      final int newDelta = parseDelta(type, qtyCtrl.text);
      final storeId = ref.read(selectedStoreProvider);
      if (storeId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No store selected')));
        }
        return;
      }
      await StoreRefs.of(storeId).stockMovements().doc(m.id).update({
        'type': type,
        'location': location,
        'deltaQty': newDelta,
        'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': user?.email,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Movement updated')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Update failed: $e')));
      }
    }
  }

  Future<void> _confirmDeleteMovement(MovementRecord m) async {
    if (m.id == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete: missing document id')));
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text('Delete Movement', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
        content: DefaultTextStyle(style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(color: Theme.of(context).colorScheme.onSurface), child: Text('Delete this movement for ${m.sku} • ${m.name}?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton.tonal(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final storeId = ref.read(selectedStoreProvider);
      if (storeId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No store selected')));
        }
        return;
      }
      await StoreRefs.of(storeId).stockMovements().doc(m.id).delete();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Movement deleted')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }
}

class MovementRecord {
  final String? id; // Firestore document id
  final DateTime date;
  final String type;
  final String sku;
  final String name;
  final String location;
  final int deltaQty;
  final int? storeAfter;
  final int? warehouseAfter;
  final int? totalAfter;
  final String? note;
  final DateTime? updatedAt;
  final String? updatedBy;
  MovementRecord({
    this.id,
    required this.date,
    required this.type,
    required this.sku,
    required this.name,
    required this.location,
    required this.deltaQty,
    this.storeAfter,
    this.warehouseAfter,
    this.totalAfter,
    this.note,
    this.updatedAt,
    this.updatedBy,
  });
}

// ---------------- Firestore persistence ----------------
// Paging controller provider for stock movements (store-scoped)
final movementsPagedControllerProvider = ChangeNotifierProvider.autoDispose<PagedListController<MovementRecord>>((ref) {
  final selStoreId = ref.watch(selectedStoreProvider);

  final controller = PagedListController<MovementRecord>(
    pageSize: 50,
    loadPage: (cursor) async {
      final after = cursor as DocumentSnapshot<Map<String, dynamic>>?;
      if (selStoreId == null) {
        // No store selected; return empty page
        return (<MovementRecord>[], null);
      }
      final query = StoreRefs.of(selStoreId)
          .stockMovements()
          .orderBy('createdAt', descending: true);
      final (items, next) = await fetchFirestorePage<MovementRecord>(
        base: query,
        after: after,
        pageSize: 50,
        map: _movementFromDoc,
      );
      return (items, next);
    },
  );

  // Trigger initial load after provider creation
  Future.microtask(controller.resetAndLoad);
  ref.onDispose(controller.dispose);
  return controller;
});

MovementRecord _movementFromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
  final m = d.data();
  DateTime? tsLocal(dynamic v) => v is Timestamp ? v.toDate() : null;
  return MovementRecord(
    id: d.id,
    date: tsLocal(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
    type: (m['type'] ?? '') as String,
    sku: (m['sku'] ?? '') as String,
    name: (m['name'] ?? '') as String,
    location: (m['location'] ?? '') as String,
    deltaQty: (m['deltaQty'] is int) ? m['deltaQty'] as int : (m['deltaQty'] is num ? (m['deltaQty'] as num).toInt() : 0),
    storeAfter: (m['storeAfter'] as num?)?.toInt(),
    warehouseAfter: (m['warehouseAfter'] as num?)?.toInt(),
    totalAfter: (m['totalAfter'] as num?)?.toInt(),
    note: m['note'] as String?,
  updatedAt: tsLocal(m['updatedAt']),
    updatedBy: m['updatedBy'] as String?,
  );
}

class _MovementDialog extends ConsumerStatefulWidget {
  const _MovementDialog();
  @override
  ConsumerState<_MovementDialog> createState() => _MovementDialogState();
}

class _MovementDialogState extends ConsumerState<_MovementDialog> {
  final _formKey = GlobalKey<FormState>();
  final _scanCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '0');
  final _noteCtrl = TextEditingController();
  String _type = 'Inbound';
  String _location = 'Store';
  ProductDoc? _selected;
  String _search = '';
  bool _submitting = false;

  @override
  void dispose() {
    _scanCtrl.dispose();
    _qtyCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
  final productsAsync = ref.watch(productsStreamProvider);
    return AlertDialog(
      title: Text('Record Stock Movement', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w700)),
      content: DefaultTextStyle(
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(color: Theme.of(context).colorScheme.onSurface),
        child: Form(
        key: _formKey,
        child: SizedBox(
          width: 520,
          child: productsAsync.when(
            data: (products) {
              final matches = _search.isEmpty
                  ? const <ProductDoc>[]
                  : products.where((p) {
                      final q = _search.toLowerCase();
            return p.sku.toLowerCase().contains(q) ||
              p.barcode.toLowerCase().contains(q) ||
              p.name.toLowerCase().contains(q);
                    }).take(8).toList();
              final currentStore = _selected?.stockAt('Store') ?? 0;
              final currentWh = _selected?.stockAt('Warehouse') ?? 0;
              // Removed preview chips; delta & predicted values no longer calculated here.
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _scanCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        labelText: 'Scan / Search SKU, Barcode or Name',
                        suffixIcon: _scanCtrl.text.isEmpty
                            ? const Icon(Icons.qr_code_scanner)
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _scanCtrl.clear();
                                    _search = '';
                                    _selected = null;
                                  });
                                },
                              ),
                      ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                      onChanged: (v) => setState(() {
                        _search = v.trim();
                        _selected = null; // reset selection if user types more
                      }),
                      onFieldSubmitted: (v) {
                        // If exactly one match, auto-select
                        if (matches.length == 1) {
                          setState(() => _selected = matches.first);
                        }
                      },
                      validator: (_) => _selected == null ? 'Select a product' : null,
                    ),
                    if (matches.isNotEmpty && _selected == null)
                      Container(
                        margin: const EdgeInsets.only(top: 6, bottom: 8),
                        constraints: const BoxConstraints(maxHeight: 220),
                        decoration: BoxDecoration(
                          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                          borderRadius: context.radiusSm,
                          color: Theme.of(context).colorScheme.surface,
                        ),
                        child: ListView.builder(
                          itemCount: matches.length,
                          itemBuilder: (_, i) {
                            final p = matches[i];
                            return ListTile(
                              dense: true,
                              title: Text('${p.sku} • ${p.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
                              subtitle: p.barcode.isNotEmpty ? Text(p.barcode) : null,
                              onTap: () => setState(() => _selected = p),
                            );
                          },
                        ),
                      ),
                    if (_selected != null) ...[
                      const SizedBox(height: 6),
                      _selectedInfo(currentStore, currentWh),
                      context.gapVMd,
                    ],
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          // initialValue removed (unsupported)
                          items: const ['Inbound', 'Outbound', 'Adjust']
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setState(() => _type = v ?? 'Inbound'),
                          decoration: const InputDecoration(labelText: 'Type'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                        ),
                      ),
                      context.gapHMd,
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          // initialValue removed (unsupported)
                          items: const ['Store', 'Warehouse']
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                          onChanged: (v) => setState(() => _location = v ?? 'Store'),
                          decoration: const InputDecoration(labelText: 'Location'),
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                        ),
                      ),
                    ]),
                    context.gapVSm,
                    TextFormField(
                      controller: _qtyCtrl,
                      decoration: InputDecoration(
                        labelText: _type == 'Adjust' ? 'Adjust Qty (can be +/-)' : 'Quantity',
                        helperText: _type == 'Outbound' ? 'Will subtract this quantity' : (_type == 'Inbound' ? 'Will add this quantity' : 'Positive or negative'),
                      ),
                      keyboardType: TextInputType.number,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final n = int.tryParse(v.trim());
                        if (n == null) return 'Invalid';
                        if (_type == 'Outbound' && n <= 0) return 'Enter positive number';
                        if (_type != 'Outbound' && _type != 'Adjust' && n < 0) return 'Cannot be negative';
                        return null;
                      },
                      onChanged: (_) => setState(() {}),
                    ),
                    context.gapVSm,
                    TextFormField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(labelText: 'Note', hintText: 'Optional remarks'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurface),
                      maxLines: 2,
                    ),
                    context.gapVMd,
                  ],
                ),
              );
            },
            error: (e, _) => SizedBox(width: 400, child: Text('Error loading products: $e')),
            loading: () => const SizedBox(width: 380, height: 160, child: Center(child: CircularProgressIndicator())),
          ),
        ),
      ),
      ),
      actions: [
        TextButton(onPressed: _submitting ? null : () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : () async {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            if (_selected == null) return;
            final repo = ref.read(inventoryRepoProvider);
            final user = ref.read(authStateProvider);
            final nav = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            final delta = _parseDelta();
            setState(() => _submitting = true);
            // Capture values needed across async gaps
            final sku = _selected!.sku;
            final name = _selected!.name;
            final noteVal = _noteCtrl.text.trim();
            ProductDoc? after;
            try {
              final storeId = ref.read(selectedStoreProvider);
              if (storeId == null) throw StateError('No store selected');
              await repo.applyStockMovement(
                storeId: storeId,
                sku: sku,
                location: _location,
                deltaQty: delta,
                type: _type,
                note: noteVal.isEmpty ? null : noteVal,
                updatedBy: user?.email,
              );
              after = await repo.getProduct(storeId, sku);
              await StoreRefs.of(storeId).stockMovements().add({
                'createdAt': FieldValue.serverTimestamp(),
                'type': _type,
                'sku': sku,
                'name': name,
                'location': _location,
                'deltaQty': delta,
                'storeAfter': after?.stockAt('Store') ?? 0,
                'warehouseAfter': after?.stockAt('Warehouse') ?? 0,
                'totalAfter': (after?.stockAt('Store') ?? 0) + (after?.stockAt('Warehouse') ?? 0),
                'note': noteVal.isEmpty ? null : noteVal,
                'updatedAt': after?.updatedAt,
                'updatedBy': after?.updatedBy,
              });
            } catch (err) {
              if (!mounted) return; // abort if unmounted
              messenger.showSnackBar(SnackBar(content: Text('Failed: $err')));
              setState(() => _submitting = false);
              return;
            }
            if (!mounted) return;
            final record = MovementRecord(
              date: DateTime.now(),
              type: _type,
              sku: sku,
              name: name,
              location: _location,
              deltaQty: delta,
              storeAfter: after?.stockAt('Store') ?? 0,
              warehouseAfter: after?.stockAt('Warehouse') ?? 0,
              totalAfter: (after?.stockAt('Store') ?? 0) + (after?.stockAt('Warehouse') ?? 0),
              note: noteVal.isEmpty ? null : noteVal,
              updatedAt: after?.updatedAt,
              updatedBy: after?.updatedBy,
            );
            if (mounted && nav.mounted) { nav.pop(record); }
          },
          child: _submitting
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Apply'),
        ),
      ],
    );
  }

  int _parseDelta() {
    final raw = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    if (_type == 'Inbound') return raw.abs();
    if (_type == 'Outbound') return -raw.abs();
    return raw; // Adjust
  }

  Widget _selectedInfo(int storeQty, int whQty) {
    final total = storeQty + whQty;
    final sizes = context.sizes;
    return Material(
      elevation: 1,
      borderRadius: context.radiusSm,
  color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: sizes.gapSm, horizontal: sizes.gapMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  _selected == null ? '' : '${_selected!.name}  (SKU: ${_selected!.sku})',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            context.gapVXs,
            Wrap(spacing: 12, runSpacing: 4, children: [
              _qtyBadge('Store', storeQty, Icons.store),
              _qtyBadge('Warehouse', whQty, Icons.warehouse),
              _qtyBadge('Total', total, Icons.summarize),
              if (_selected?.updatedAt != null)
                Text('Updated: ${_fmtDateTime(_selected!.updatedAt!)}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              if ((_selected?.updatedBy ?? '').isNotEmpty)
                Text('By: ${_selected!.updatedBy}', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _qtyBadge(String label, int value, IconData icon) {
    final sizes = context.sizes;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: context.radiusLg,
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: sizes.iconXs, color: Theme.of(context).colorScheme.onSurfaceVariant),
        SizedBox(width: sizes.gapXs),
        Text('$label: $value', style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }

  // Preview row & diff chips removed per user request.
}

String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
String _fmtDateTime(DateTime d) => '${_fmtDate(d)} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
