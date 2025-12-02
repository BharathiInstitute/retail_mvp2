// Loyalty Customer Browser
// Features:
//  - Search + filter customers
//  - Inline change of status (tier) per customer
//  - Read-only display of current global tier definitions (from loyalty_config doc)
// Removed (migrated to new LoyaltySettingsScreen): plan editing dialog, batch apply logic, overlay progress, cancellation.

// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../crm/crm_screen.dart' show CrmCustomer, LoyaltyStatus, LoyaltyFilter, LoyaltyFilterX; // reuse existing models
import 'loyalty_program_settings_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retail_mvp2/core/firestore_store_collections.dart';
import 'package:retail_mvp2/modules/stores/providers.dart';
import '../../core/theme/theme_extension_helpers.dart';

class LoyaltyModuleScreen extends ConsumerStatefulWidget {
  const LoyaltyModuleScreen({super.key});
  @override
  ConsumerState<LoyaltyModuleScreen> createState() => _LoyaltyModuleScreenState();
}

class _LoyaltyModuleScreenState extends ConsumerState<LoyaltyModuleScreen> {
  String _search = '';
  LoyaltyFilter _filter = LoyaltyFilter.all;
  bool _ready = false;
  // Removed apply-related state; only simple browsing now.

  @override
  void initState() {
    super.initState();
    _ensureAuthed().then((_) { if (mounted) setState(()=>_ready = true); });
  }

  Future<void> _ensureAuthed() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) { await auth.signInAnonymously(); }
  }

  // -------- Data Streams --------
  Stream<List<CrmCustomer>> _customers() {
    final sid = ref.read(selectedStoreIdProvider);
    if (sid == null) return const Stream.empty();
    return StoreRefs.of(sid).customers().snapshots().map((s){
      final list = s.docs.map((d)=>CrmCustomer.fromDoc(d)).toList();
      list.sort((a,b)=>a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      return list;
    });
  }

  List<CrmCustomer> _filtered(List<CrmCustomer> input){
    final q = _search.trim().toLowerCase();
    return input.where((c){
      final matchQ = q.isEmpty || c.name.toLowerCase().contains(q) || c.phone.toLowerCase().contains(q) || c.email.toLowerCase().contains(q);
      final matchTier = _filter == LoyaltyFilter.all || _filter.status == c.status;
      return matchQ && matchTier;
    }).toList();
  }

  // Read-only global tier info now derived from loyalty_config tiers list.
  Stream<List<_TierView>> _tierConfig() {
    final sid = ref.read(selectedStoreIdProvider);
    if (sid == null) return const Stream.empty();
    return StoreRefs.of(sid)
      .loyaltySettings()
      .doc('config')
      .snapshots()
      .map((d){
        final data = d.data() ?? {};
        final raw = data['tiers'];
        if(raw is List){
          return raw.map((e){
            final m = e as Map;
            return _TierView(
              name: (m['name']??'').toString(),
              minSpend: (m['minSpend'] is num)? (m['minSpend'] as num).toDouble(): double.tryParse('${m['minSpend']}') ?? 0,
              discount: (m['discount'] is num)? (m['discount'] as num).toDouble(): double.tryParse('${m['discount']}') ?? 0,
            );
          }).toList();
        }
        return <_TierView>[];
      });
  }

  // Removed _editPlans and propagation logic.

  // -------- UI --------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if(!_ready) return const Center(child: CircularProgressIndicator());
    return StreamBuilder<List<_TierView>>(
      stream: _tierConfig(),
      builder: (context, snap) {
        final tiers = snap.data ?? const <_TierView>[];
        final isMobile = MediaQuery.of(context).size.width < 560;
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [cs.primary.withOpacity(0.04), cs.surface],
              stops: const [0.0, 0.3],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(isMobile ? 8 : 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Modern search/action bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: context.radiusMd,
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    // Search field
                    Container(
                      width: isMobile ? 180 : 220,
                      height: 34,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.4),
                        borderRadius: context.radiusSm,
                      ),
                      child: TextField(
                        style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded, size: 18, color: cs.onSurfaceVariant),
                          hintText: 'Search customers',
                          hintStyle: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant),
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onChanged: (v) => setState(() => _search = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Filter dropdown
                    Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(0.4),
                        borderRadius: context.radiusSm,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<LoyaltyFilter>(
                          value: _filter,
                          style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface),
                          dropdownColor: cs.surface,
                          iconSize: 18,
                          iconEnabledColor: cs.onSurfaceVariant,
                          items: const [
                            DropdownMenuItem(value: LoyaltyFilter.all, child: Text('All')),
                            DropdownMenuItem(value: LoyaltyFilter.bronze, child: Text('Bronze')),
                            DropdownMenuItem(value: LoyaltyFilter.silver, child: Text('Silver')),
                            DropdownMenuItem(value: LoyaltyFilter.gold, child: Text('Gold')),
                          ],
                          onChanged: (v) => setState(() => _filter = v ?? LoyaltyFilter.all),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Settings button
                    _ModernLoyaltyButton(
                      icon: Icons.settings_rounded,
                      label: 'Settings',
                      color: cs.primary,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const LoyaltySettingsScreen()),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              // Customer list
              Expanded(child: _customerList(tiers)),
              if (!isMobile) ...[
                const SizedBox(height: 10),
                _plansSummary(tiers),
              ]
            ]),
          ),
        );
      }
    );
  }

  Widget _customerList(List<_TierView> tiers){
    final cs = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: ClipRRect(
        borderRadius: context.radiusMd,
        child: StreamBuilder<List<CrmCustomer>>(
          stream: _customers(),
          builder: (context, snap) {
            if (snap.hasError) return Center(child: Text('Error: ${snap.error}', style: TextStyle(fontSize: context.sizes.fontSm, color: cs.error)));
            if (!snap.hasData) return Center(child: Padding(padding: context.padXl, child: const CircularProgressIndicator()));
            final list = _filtered(snap.data!);
            if (list.isEmpty) return Center(child: Text('No customers', style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant)));
            return ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final c = list[i];
                final tier = _findTierForStatus(tiers, c.status);
                double pts = c.loyaltyPoints;
                String fmtPts() {
                  final s = pts.toStringAsFixed(1);
                  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
                }
                return _ModernCustomerRow(
                  customer: c,
                  tier: tier,
                  isEven: i.isEven,
                  fmtPts: fmtPts,
                  onStatusChanged: (newStatus) async {
                    if (newStatus == null || newStatus == c.status) return;
                    final messenger = ScaffoldMessenger.of(context);
                    final newTier = _findTierForStatus(tiers, newStatus);
                    final newPoints = (c.totalSpend / 100.0) * (newTier?.pointsPer100 ?? 1.0);
                    try {
                      final sid = ref.read(selectedStoreIdProvider);
                      if (sid == null) throw Exception('No store selected');
                      await StoreRefs.of(sid).customers().doc(c.id).update({
                        'status': newStatus.name,
                        'loyaltyDiscount': newTier?.discount ?? 0,
                        'loyaltyRate': newTier?.pointsPer100 ?? 1.0,
                        'loyaltyPoints': newPoints,
                        'loyaltyUpdatedAt': FieldValue.serverTimestamp(),
                      });
                    } catch (e) {
                      messenger.showSnackBar(SnackBar(content: Text('Update failed: $e')));
                    }
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _plansSummary(List<_TierView> tiers) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: context.padMd,
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.workspace_premium_rounded, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text('Current Tiers (read-only)', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ]),
        const SizedBox(height: 10),
        if (tiers.isEmpty)
          Text('No tier configuration found (open settings to configure).', style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurfaceVariant))
        else
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (int i = 0; i < tiers.length; i++) _ModernTierCard(tier: tiers[i], color: _tierColor(context, i)),
            ],
          )
      ]),
    );
  }

  _TierView? _findTierForStatus(List<_TierView> tiers, LoyaltyStatus status){
    // naive mapping by index: 0=bronze,1=silver,2=gold fallback
    if(tiers.isEmpty) return null;
    switch(status){
      case LoyaltyStatus.bronze: return tiers.isNotEmpty? tiers[0]: null;
      case LoyaltyStatus.silver: return tiers.length>1? tiers[1]: tiers.last;
      case LoyaltyStatus.gold: return tiers.length>2? tiers[2]: tiers.last;
    }
  }

  Color _tierColor(BuildContext context, int i){
    final scheme = Theme.of(context).colorScheme;
    switch(i){
      case 0: return scheme.tertiary; // bronze-like
      case 1: return scheme.secondary; // silver-like
      case 2: return scheme.primary; // gold-like
      default: return scheme.primaryContainer;
    }
  }
}

class _TierView {
  final String name; final double minSpend; final double discount;
  const _TierView({required this.name, required this.minSpend, required this.discount});
  double get pointsPer100 => 1.0; // Placeholder if future logic adds points differential per tier
}

// Modern action button widget
class _ModernLoyaltyButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ModernLoyaltyButton({required this.icon, required this.label, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radiusSm,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: context.radiusSm,
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w500, color: color)),
          ]),
        ),
      ),
    );
  }
}

// Modern customer row widget
class _ModernCustomerRow extends StatelessWidget {
  final CrmCustomer customer;
  final _TierView? tier;
  final bool isEven;
  final String Function() fmtPts;
  final Function(LoyaltyStatus?) onStatusChanged;
  const _ModernCustomerRow({required this.customer, required this.tier, required this.isEven, required this.fmtPts, required this.onStatusChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = customer;
    return Container(
      color: isEven ? Colors.transparent : cs.surfaceContainerHighest.withOpacity(0.2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(children: [
        // Avatar
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.1),
            borderRadius: context.radiusSm,
          ),
          child: Center(child: Text(c.initials, style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.primary))),
        ),
        context.gapHMd,
        // Name & contact
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.name, style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: cs.onSurface)),
            const SizedBox(height: 2),
            Text('${c.email} • ${c.phone}', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant), overflow: TextOverflow.ellipsis),
          ]),
        ),
        context.gapHSm,
        // Status dropdown
        Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.4),
            borderRadius: context.radiusSm,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<LoyaltyStatus>(
              value: c.status,
              style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurface),
              dropdownColor: cs.surface,
              iconSize: 16,
              iconEnabledColor: cs.onSurfaceVariant,
              items: const [
                DropdownMenuItem(value: LoyaltyStatus.bronze, child: Text('Bronze')),
                DropdownMenuItem(value: LoyaltyStatus.silver, child: Text('Silver')),
                DropdownMenuItem(value: LoyaltyStatus.gold, child: Text('Gold')),
              ],
              onChanged: onStatusChanged,
            ),
          ),
        ),
        context.gapHSm,
        // Points badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: cs.primary.withOpacity(0.08),
            borderRadius: context.radiusSm,
          ),
          child: Text('${fmtPts()} pts', style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w500, color: cs.primary)),
        ),
        const SizedBox(width: 6),
        // Discount badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: cs.secondary.withOpacity(0.08),
            borderRadius: context.radiusSm,
          ),
          child: Text('${(tier?.discount ?? 0).toStringAsFixed(0)}%', style: TextStyle(fontSize: context.sizes.fontXs, fontWeight: FontWeight.w500, color: cs.secondary)),
        ),
      ]),
    );
  }
}

// Modern tier card widget
class _ModernTierCard extends StatelessWidget {
  final _TierView tier;
  final Color color;
  const _ModernTierCard({required this.tier, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: context.radiusMd,
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.workspace_premium_rounded, size: 16, color: color),
          const SizedBox(width: 6),
          Text(tier.name, style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: color)),
        ]),
        context.gapVSm,
        Wrap(spacing: 6, runSpacing: 6, children: [
          _MiniChip(text: '${tier.pointsPer100.toStringAsFixed(2)} pts / ₹100'),
          _MiniChip(text: '${tier.discount.toStringAsFixed(0)}% discount'),
        ]),
      ]),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String text;
  const _MiniChip({required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: context.radiusSm,
      ),
      child: Text(text, style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant)),
    );
  }
}

