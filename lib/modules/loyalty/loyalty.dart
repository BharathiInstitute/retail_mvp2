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
import '../crm/crm.dart' show CrmCustomer, LoyaltyStatus, LoyaltyFilter, LoyaltyFilterX; // reuse existing models
import 'loyalty_settings.dart';

class LoyaltyModuleScreen extends StatefulWidget {
  const LoyaltyModuleScreen({super.key});
  @override
  State<LoyaltyModuleScreen> createState() => _LoyaltyModuleScreenState();
}

class _LoyaltyModuleScreenState extends State<LoyaltyModuleScreen> {
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
  Stream<List<CrmCustomer>> _customers() => FirebaseFirestore.instance.collection('customers').snapshots().map((s){
    final list = s.docs.map((d)=>CrmCustomer.fromDoc(d)).toList();
    list.sort((a,b)=>a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  });

  List<CrmCustomer> _filtered(List<CrmCustomer> input){
    final q = _search.trim().toLowerCase();
    return input.where((c){
      final matchQ = q.isEmpty || c.name.toLowerCase().contains(q) || c.phone.toLowerCase().contains(q) || c.email.toLowerCase().contains(q);
      final matchTier = _filter == LoyaltyFilter.all || _filter.status == c.status;
      return matchQ && matchTier;
    }).toList();
  }

  // Read-only global tier info now derived from loyalty_config tiers list.
  Stream<List<_TierView>> _tierConfig() => FirebaseFirestore.instance
      .collection('settings')
      .doc('loyalty_config')
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

  // Removed _editPlans and propagation logic.

  // -------- UI --------
  @override
  Widget build(BuildContext context) {
    if(!_ready) return const Center(child: CircularProgressIndicator());
    return StreamBuilder<List<_TierView>>(
      stream: _tierConfig(),
      builder: (context, snap) {
        final tiers = snap.data ?? const <_TierView>[];
        return Stack(children:[
          Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing:12, runSpacing:12, children:[
              SizedBox(width:260, child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search customers'),
                onChanged: (v)=>setState(()=>_search=v),
              )),
              DropdownButton<LoyaltyFilter>(
                value: _filter,
                items: const [
                  DropdownMenuItem(value: LoyaltyFilter.all, child: Text('All')),
                  DropdownMenuItem(value: LoyaltyFilter.bronze, child: Text('Bronze')),
                  DropdownMenuItem(value: LoyaltyFilter.silver, child: Text('Silver')),
                  DropdownMenuItem(value: LoyaltyFilter.gold, child: Text('Gold')),
                ],
                onChanged: (v)=>setState(()=>_filter=v??LoyaltyFilter.all),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const LoyaltySettingsScreen()),
                  );
                },
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Settings'),
              ),
            ]),
            const SizedBox(height:16),
            Expanded(child: _customerList(tiers)),
            const SizedBox(height:12),
            _plansSummary(tiers),
          ]),
        ),
        ]);
      }
    );
  }

  Widget _customerList(List<_TierView> tiers){
    return Card(
      child: StreamBuilder<List<CrmCustomer>>(
        stream: _customers(),
        builder:(context,snap){
          if(snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if(!snap.hasData) return const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()));
          final list = _filtered(snap.data!);
          if(list.isEmpty) return const Center(child: Text('No customers'));
          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height:1),
            itemBuilder: (context,i){
              final c = list[i];
              final tier = _findTierForStatus(tiers, c.status);
              // Use stored loyaltyPoints directly (added to CrmCustomer model)
              double pts = c.loyaltyPoints;
              String fmtPts(){
                final s = pts.toStringAsFixed(1);
                return s.endsWith('.0')? s.substring(0,s.length-2): s;
              }
              return ListTile(
                leading: CircleAvatar(child: Text(c.initials)),
                title: Text(c.name),
                subtitle: Text('${c.email} • ${c.phone}'),
                trailing: Wrap(spacing:6, crossAxisAlignment: WrapCrossAlignment.center, children:[
                  DropdownButton<LoyaltyStatus>(
                    value: c.status,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: LoyaltyStatus.bronze, child: Text('Bronze')),
                      DropdownMenuItem(value: LoyaltyStatus.silver, child: Text('Silver')),
                      DropdownMenuItem(value: LoyaltyStatus.gold, child: Text('Gold')),
                    ],
                    onChanged: (newStatus) async {
                      if(newStatus==null || newStatus==c.status) return;
                      final messenger = ScaffoldMessenger.of(context); // capture before async
                      final newTier = _findTierForStatus(tiers, newStatus);
                      final newPoints = (c.totalSpend/100.0)*(newTier?.pointsPer100 ?? 1.0);
                      try {
                        await FirebaseFirestore.instance.collection('customers').doc(c.id).update({
                          'status': newStatus.name,
                          'loyaltyDiscount': newTier?.discount ?? 0,
                          'loyaltyRate': newTier?.pointsPer100 ?? 1.0,
                          'loyaltyPoints': newPoints,
                          'loyaltyUpdatedAt': FieldValue.serverTimestamp(),
                        });
                      } catch(e){
                        if(!mounted) return; messenger.showSnackBar(SnackBar(content: Text('Update failed: $e')));
                      }
                    },
                  ),
                  Chip(label: Text('${fmtPts()} pts')),
                  Chip(label: Text('${(tier?.discount ?? 0).toStringAsFixed(0)}%')),
                ]),
              );
            },
          );
        }
      ),
    );
  }

  Widget _plansSummary(List<_TierView> tiers){
    Widget tile(_TierView t, Color c)=>ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: .35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Row(children:[Icon(Icons.workspace_premium_outlined, color:c), const SizedBox(width:6), Text(t.name, style: TextStyle(color:c,fontWeight:FontWeight.w600))]),
          const SizedBox(height:8),
          Wrap(spacing:8, runSpacing: 8, children:[
            Chip(label: Text('${t.pointsPer100.toStringAsFixed(2)} pts / ₹100')),
            Chip(label: Text('${t.discount.toStringAsFixed(0)}% discount')),
          ])
        ]),
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Text('Current Tiers (read-only)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height:8),
          if(tiers.isEmpty) const Text('No tier configuration found (open settings to configure).') else Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (int i = 0; i < tiers.length; i++) tile(tiers[i], _tierColor(i)),
            ],
          )
        ]),
      ),
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

  Color _tierColor(int i){
    switch(i){
      case 0: return Colors.brown;
      case 1: return Colors.blueGrey;
      case 2: return Colors.amber;
      default: return Colors.purple;
    }
  }
}

class _TierView {
  final String name; final double minSpend; final double discount;
  const _TierView({required this.name, required this.minSpend, required this.discount});
  double get pointsPer100 => 1.0; // Placeholder if future logic adds points differential per tier
}

