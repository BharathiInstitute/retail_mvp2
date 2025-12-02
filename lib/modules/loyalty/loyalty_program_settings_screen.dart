// Loyalty Settings Admin Screen
// Implements configurable points rules + tier management.
// Firestore document: settings/loyalty_config
// Fields:
//  pointsPerCurrency (double)
//  minRedeemPoints (int)
//  expiryMonths (int|null)
//  tiers: [ { name, minSpend, discount } ]
//  updatedAt (server timestamp)
// NOTE: This screen only edits configuration; it does NOT propagate changes to customers.

// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retail_mvp2/core/firestore_store_collections.dart';
import 'package:retail_mvp2/modules/stores/providers.dart';
import '../../core/theme/theme_extension_helpers.dart';

// ------------------ Data Models ------------------

class LoyaltyTier {
  final String name;
  final double minSpend;
  final double discount; // percent 0-100
  const LoyaltyTier({required this.name, required this.minSpend, required this.discount});

  LoyaltyTier copyWith({String? name, double? minSpend, double? discount}) => LoyaltyTier(
    name: name ?? this.name,
    minSpend: minSpend ?? this.minSpend,
    discount: discount ?? this.discount,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'minSpend': minSpend,
    'discount': discount,
  };
  static LoyaltyTier fromMap(Map<String, dynamic> m) => LoyaltyTier(
    name: (m['name'] ?? '').toString(),
    minSpend: (m['minSpend'] is num) ? (m['minSpend'] as num).toDouble() : double.tryParse('${m['minSpend']}') ?? 0,
    discount: (m['discount'] is num) ? (m['discount'] as num).toDouble() : double.tryParse('${m['discount']}') ?? 0,
  );
}

class LoyaltySettings {
  final double pointsPerCurrency; // points earned per 1 currency unit (₹1)
  final int minRedeemPoints;
  final int? expiryMonths; // null => no expiry
  final List<LoyaltyTier> tiers;
  const LoyaltySettings({
    required this.pointsPerCurrency,
    required this.minRedeemPoints,
    required this.expiryMonths,
    required this.tiers,
  });

  LoyaltySettings copyWith({
    double? pointsPerCurrency,
    int? minRedeemPoints,
    int? expiryMonths, // pass -1 to clear
    List<LoyaltyTier>? tiers,
  }) => LoyaltySettings(
    pointsPerCurrency: pointsPerCurrency ?? this.pointsPerCurrency,
    minRedeemPoints: minRedeemPoints ?? this.minRedeemPoints,
    expiryMonths: (expiryMonths == -1) ? null : expiryMonths ?? this.expiryMonths,
    tiers: tiers ?? this.tiers,
  );

  Map<String, dynamic> toMap() => {
    'pointsPerCurrency': pointsPerCurrency,
    'minRedeemPoints': minRedeemPoints,
    if (expiryMonths != null) 'expiryMonths': expiryMonths,
    'tiers': tiers.map((t) => t.toMap()).toList(),
    'updatedAt': FieldValue.serverTimestamp(),
  };

  static LoyaltySettings fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final pts = (d['pointsPerCurrency'] is num) ? (d['pointsPerCurrency'] as num).toDouble() : double.tryParse('${d['pointsPerCurrency']}') ?? 0.01;
    final minRedeem = d['minRedeemPoints'] is num ? (d['minRedeemPoints'] as num).toInt() : int.tryParse('${d['minRedeemPoints']}') ?? 0;
    final exp = d['expiryMonths'] is num ? (d['expiryMonths'] as num).toInt() : int.tryParse('${d['expiryMonths']}');
    final rawTiers = (d['tiers'] is List) ? (d['tiers'] as List) : const [];
    final tiers = rawTiers.map((e) => LoyaltyTier.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    return LoyaltySettings(pointsPerCurrency: pts, minRedeemPoints: minRedeem, expiryMonths: exp, tiers: tiers.isEmpty ? _defaultTiers : tiers);
  }

  static const List<LoyaltyTier> _defaultTiers = [
    LoyaltyTier(name: 'Bronze', minSpend: 0, discount: 0),
    LoyaltyTier(name: 'Silver', minSpend: 10000, discount: 5),
    LoyaltyTier(name: 'Gold', minSpend: 20000, discount: 10),
  ];

  static LoyaltySettings defaults() => const LoyaltySettings(
    pointsPerCurrency: 0.01, // 1 point per ₹100
    minRedeemPoints: 500,
    expiryMonths: null,
    tiers: _defaultTiers,
  );
}

// ------------------ Repository ------------------

class LoyaltySettingsRepository {
  final DocumentReference<Map<String, dynamic>> _doc;
  LoyaltySettingsRepository(this._doc);

  Future<LoyaltySettings> fetch() async {
    final snap = await _doc.get();
    if (!snap.exists) {
      // create defaults
      final def = LoyaltySettings.defaults();
      await _doc.set(def.toMap(), SetOptions(merge: true));
      return def;
    }
    return LoyaltySettings.fromDoc(snap);
  }

  Future<void> save(LoyaltySettings s) async {
    await _doc.set(s.toMap(), SetOptions(merge: true));
  }
}

// ------------------ Screen ------------------

class LoyaltySettingsScreen extends ConsumerStatefulWidget {
  const LoyaltySettingsScreen({super.key});
  @override
  ConsumerState<LoyaltySettingsScreen> createState() => _LoyaltySettingsScreenState();
}

class _LoyaltySettingsScreenState extends ConsumerState<LoyaltySettingsScreen> {
  LoyaltySettingsRepository? _repo;

  bool _loading = true;
  String? _error;
  LoyaltySettings? _original; // loaded snapshot
  LoyaltySettings? _current;  // mutable edits

  // Controllers
  final _pointsCtrl = TextEditingController();
  final _minRedeemCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _simSpendCtrl = TextEditingController(text: '2500'); // persistent controller for preview spend

  // Validation cache
  String? _pointsErr; String? _redeemErr; String? _expiryErr; String? _tiersErr;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Defer load until we can read storeId from provider in didChangeDependencies
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_repo == null) {
      final sid = ref.read(selectedStoreIdProvider);
      if (sid != null) {
        final doc = StoreRefs.of(sid).loyaltySettings().doc('config');
        _repo = LoyaltySettingsRepository(doc);
        _load();
      }
    }
  }

  Future<void> _load() async {
    setState(()=> _loading = true);
    try {
      if (_repo == null) throw Exception('No store selected');
      final s = await _repo!.fetch();
      _original = s;
      _current = s;
      _bindControllers(s);
      _validateAll();
      setState(()=> _loading = false);
    } catch(e){
      setState(()=> _error = e.toString());
      setState(()=> _loading = false);
    }
  }

  void _bindControllers(LoyaltySettings s){
    _pointsCtrl.text = s.pointsPerCurrency.toString();
    _minRedeemCtrl.text = s.minRedeemPoints.toString();
    _expiryCtrl.text = s.expiryMonths?.toString() ?? '';
  }

  bool get _dirty => _current != null && _original != null && (
    _current!.pointsPerCurrency != _original!.pointsPerCurrency ||
    _current!.minRedeemPoints != _original!.minRedeemPoints ||
    _current!.expiryMonths != _original!.expiryMonths ||
    _tiersChanged()
  );

  bool _tiersChanged(){
    final a = _original!.tiers; final b = _current!.tiers;
    if (a.length != b.length) return true;
    for (int i=0;i<a.length;i++){
      if(a[i].name!=b[i].name || a[i].minSpend!=b[i].minSpend || a[i].discount!=b[i].discount) return true;
    }
    return false;
  }

  void _validateAll(){
    _pointsErr = _validatePoints(_pointsCtrl.text);
    _redeemErr = _validateMinRedeem(_minRedeemCtrl.text);
    _expiryErr = _validateExpiry(_expiryCtrl.text);
    _tiersErr = _validateTiers(_current?.tiers ?? []);
  }

  String? _validatePoints(String v){
    final d = double.tryParse(v); if(d==null || d<=0) return 'Must be > 0'; return null; }
  String? _validateMinRedeem(String v){ final i = int.tryParse(v); if(i==null||i<0) return 'Invalid'; return null; }
  String? _validateExpiry(String v){ if(v.trim().isEmpty) return null; final i = int.tryParse(v); if(i==null||i<=0||i>60) return '1-60 months'; return null; }
  String? _validateTiers(List<LoyaltyTier> tiers){
    if(tiers.isEmpty) return 'At least one tier required';
    if(tiers.first.minSpend != 0) return 'First tier min spend must be 0';
    final names = <String>{};
    double prev = -1;
    for(final t in tiers){
      if(t.name.trim().isEmpty) return 'Empty tier name';
      final lower = t.name.toLowerCase();
      if(!names.add(lower)) return 'Duplicate tier name: ${t.name}';
      if(t.minSpend < 0) return 'Negative spend in ${t.name}';
      if(t.discount < 0 || t.discount > 100) return 'Discount out of range in ${t.name}';
      if(prev > t.minSpend) return 'Tiers not sorted by min spend';
      prev = t.minSpend;
    }
    return null;
  }

  void _updateCurrentFromControllers(){
    if(_current==null) return;
    final pts = double.tryParse(_pointsCtrl.text) ?? _current!.pointsPerCurrency;
    final minRedeem = int.tryParse(_minRedeemCtrl.text) ?? _current!.minRedeemPoints;
    final expiry = _expiryCtrl.text.trim().isEmpty ? null : int.tryParse(_expiryCtrl.text);
    _current = _current!.copyWith(pointsPerCurrency: pts, minRedeemPoints: minRedeem, expiryMonths: expiry);
  }

  Future<void> _save() async {
    _updateCurrentFromControllers();
    _validateAll();
    if([_pointsErr,_redeemErr,_expiryErr,_tiersErr].any((e)=>e!=null)) { setState((){}); return; }
    if(!_dirty) return;
    setState(()=> _saving = true);
    try {
      if (_repo == null) throw Exception('No store selected');
      await _repo!.save(_current!);
      _original = _current; // snapshot baseline
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loyalty settings updated')));
    } catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally { if(mounted) setState(()=> _saving = false); }
  }

  void _resetDefaults() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) {
        final scheme = Theme.of(context).colorScheme;
        final texts = Theme.of(context).textTheme;
        return AlertDialog(
          title: Text(
            'Reset to Defaults',
            style: texts.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
          ),
          content: DefaultTextStyle(
            style: texts.bodyMedium?.copyWith(color: scheme.onSurface) ?? const TextStyle(),
            child: const Text(
              'Revert all loyalty settings to default values? This does not affect existing customer documents.',
            ),
          ),
          actions: [
            TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: ()=>Navigator.pop(context,true),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );
    if(ok!=true) return;
    final def = LoyaltySettings.defaults();
    setState((){ _current = def; _bindControllers(def); _validateAll(); });
  }

  void _addTier() async {
    final res = await showDialog<LoyaltyTier>(context: context, builder: (_)=> _TierDialog());
    if(res==null) return;
    final list = [..._current!.tiers, res];
    list.sort((a,b)=> a.minSpend.compareTo(b.minSpend));
    setState((){ _current = _current!.copyWith(tiers: list); _validateAll(); });
  }

  void _editTier(int index) async {
    final tier = _current!.tiers[index];
    final res = await showDialog<LoyaltyTier>(context: context, builder: (_)=> _TierDialog(existing: tier));
    if(res==null) return;
    final list = [..._current!.tiers];
    list[index] = res;
    list.sort((a,b)=> a.minSpend.compareTo(b.minSpend));
    setState((){ _current = _current!.copyWith(tiers: list); _validateAll(); });
  }

  void _deleteTier(int index){
    final list = [..._current!.tiers];
    if(list.length==1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot remove last tier')));
      return;
    }
    list.removeAt(index);
    setState((){ _current = _current!.copyWith(tiers: list); _validateAll(); });
  }

  void _reorder(int oldIndex, int newIndex){
    final list = [..._current!.tiers];
    if(newIndex>oldIndex) { newIndex--; }
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    list.sort((a,b)=> a.minSpend.compareTo(b.minSpend));
    setState((){ _current = _current!.copyWith(tiers: list); _validateAll(); });
  }

  @override
  void dispose(){
    _pointsCtrl.dispose(); _minRedeemCtrl.dispose(); _expiryCtrl.dispose(); _simSpendCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if(_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if(_error!=null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children:[
  Icon(Icons.error_outline, size: 40, color: Theme.of(context).colorScheme.error),
        context.gapVMd,
        Text('Failed loading loyalty settings', style: Theme.of(context).textTheme.titleMedium),
        Padding(padding: context.padSm, child: Text(_error!, textAlign: TextAlign.center)),
        FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]));
    }

    final tiers = _current!.tiers;
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder:(context, constraints){
      final wide = constraints.maxWidth > 980;
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text('Loyalty Settings', style: TextStyle(fontSize: context.sizes.fontLg, fontWeight: FontWeight.w600, color: cs.onSurface)),
          actions: [
            _ModernSettingsButton(
              icon: Icons.restore_rounded,
              label: 'Defaults',
              color: cs.secondary,
              onTap: _resetDefaults,
            ),
            context.gapHMd,
          ],
        ),
        body: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [cs.primary.withOpacity(0.04), cs.surface],
              stops: const [0.0, 0.3],
            ),
          ),
          child: SingleChildScrollView(
            padding: context.padMd,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (wide)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 340, child: _pointsRulesCard()),
                      context.gapHMd,
                      Expanded(child: _tiersCard(tiers)),
                    ])
                  else ...[  
                    _pointsRulesCard(),
                    context.gapVMd,
                    _tiersCard(tiers),
                  ],
                  const SizedBox(height: 100), // space for FAB region
                ]),
              ),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: _saveFab(),
      );
    });
  }

  Widget _pointsRulesCard(){
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.tune_rounded, size: 16, color: cs.primary),
          context.gapHSm,
          Text('Points Rules', style: TextStyle(fontSize: context.sizes.fontMd, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ]),
        const SizedBox(height: 14),
        _ModernSettingsField(
          controller: _pointsCtrl,
          label: 'Points per ₹1',
          errorText: _pointsErr,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) { _updateCurrentFromControllers(); _validateAll(); setState(() {}); },
        ),
        const SizedBox(height: 10),
        _ModernSettingsField(
          controller: _minRedeemCtrl,
          label: 'Minimum redeem points',
          errorText: _redeemErr,
          keyboardType: TextInputType.number,
          onChanged: (_) { _updateCurrentFromControllers(); _validateAll(); setState(() {}); },
        ),
        const SizedBox(height: 10),
        _ModernSettingsField(
          controller: _expiryCtrl,
          label: 'Points expiry (months, blank = none)',
          errorText: _expiryErr,
          keyboardType: TextInputType.number,
          onChanged: (_) { _updateCurrentFromControllers(); _validateAll(); setState(() {}); },
        ),
        if (_tiersErr != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_tiersErr!, style: TextStyle(fontSize: context.sizes.fontXs, color: cs.error)),
          )
      ]),
    );
  }

  Widget _tiersCard(List<LoyaltyTier> tiers){
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.workspace_premium_rounded, size: 16, color: cs.primary),
          context.gapHSm,
          Text('Tiers', style: TextStyle(fontSize: context.sizes.fontMd, fontWeight: FontWeight.w600, color: cs.onSurface)),
        ]),
        const SizedBox(height: 10),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tiers.length,
          onReorder: _reorder,
          itemBuilder: (_, i) {
            final t = tiers[i];
            return _ModernTierRow(
              key: ValueKey('tier-$i-${t.name}'),
              tier: t,
              onEdit: () => _editTier(i),
              onDelete: () => _deleteTier(i),
            );
          },
        ),
        const SizedBox(height: 10),
        _ModernSettingsButton(
          icon: Icons.add_rounded,
          label: 'Add Tier',
          color: cs.primary,
          onTap: _addTier,
          outlined: true,
        ),
      ]),
    );
  }

  Widget _saveFab(){
    final cs = Theme.of(context).colorScheme;
    final disabled = _saving || !_dirty || [_pointsErr,_redeemErr,_expiryErr,_tiersErr].any((e)=>e!=null);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: disabled ? null : _save,
        borderRadius: context.radiusMd,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: disabled ? cs.surfaceContainerHighest : cs.primary.withOpacity(0.15),
            borderRadius: context.radiusMd,
            border: Border.all(color: disabled ? cs.outlineVariant.withOpacity(0.3) : cs.primary.withOpacity(0.4)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _saving
                ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary))
                : Icon(Icons.save_rounded, size: 18, color: disabled ? cs.onSurfaceVariant : cs.primary),
            context.gapHSm,
            Text(
              _saving ? 'Saving...' : 'Save Changes',
              style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w600, color: disabled ? cs.onSurfaceVariant : cs.primary),
            ),
          ]),
        ),
      ),
    );
  }
}

// Modern settings field widget
class _ModernSettingsField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? errorText;
  final TextInputType? keyboardType;
  final Function(String)? onChanged;
  const _ModernSettingsField({required this.controller, required this.label, this.errorText, this.keyboardType, this.onChanged});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant)),
      context.gapVXs,
      Container(
        height: 36,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(0.4),
          borderRadius: context.radiusSm,
          border: errorText != null ? Border.all(color: cs.error) : null,
        ),
        child: TextField(
          controller: controller,
          style: TextStyle(fontSize: context.sizes.fontSm, color: cs.onSurface),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          ),
          keyboardType: keyboardType,
          onChanged: onChanged,
        ),
      ),
      if (errorText != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(errorText!, style: TextStyle(fontSize: context.sizes.fontXs, color: cs.error)),
        ),
    ]);
  }
}

// Modern settings button widget
class _ModernSettingsButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;
  const _ModernSettingsButton({required this.icon, required this.label, required this.color, required this.onTap, this.outlined = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radiusSm,
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: outlined ? Colors.transparent : color.withOpacity(0.1),
            borderRadius: context.radiusSm,
            border: Border.all(color: outlined ? cs.outlineVariant.withOpacity(0.5) : color.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: outlined ? cs.onSurfaceVariant : color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w500, color: outlined ? cs.onSurface : color)),
          ]),
        ),
      ),
    );
  }
}

// Modern tier row widget
class _ModernTierRow extends StatelessWidget {
  final LoyaltyTier tier;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ModernTierRow({super.key, required this.tier, required this.onEdit, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.2),
        borderRadius: context.radiusSm,
      ),
      child: Row(children: [
        Icon(Icons.drag_handle_rounded, size: 18, color: cs.onSurfaceVariant.withOpacity(0.5)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${tier.name} • Min ₹${tier.minSpend.toStringAsFixed(0)}', style: TextStyle(fontSize: context.sizes.fontSm, fontWeight: FontWeight.w500, color: cs.onSurface)),
            Text('Discount ${tier.discount.toStringAsFixed(1)}%', style: TextStyle(fontSize: context.sizes.fontXs, color: cs.onSurfaceVariant)),
          ]),
        ),
        _MiniIconButton(icon: Icons.edit_rounded, onTap: onEdit),
        context.gapHXs,
        _MiniIconButton(icon: Icons.delete_rounded, onTap: onDelete),
        context.gapHXs,
        Icon(Icons.drag_indicator_rounded, size: 16, color: cs.onSurfaceVariant.withOpacity(0.5)),
      ]),
    );
  }
}

class _MiniIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MiniIconButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: context.radiusSm,
        child: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: context.radiusSm,
          ),
          child: Icon(icon, size: 14, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ------------------ Tier Dialog ------------------

class _TierDialog extends StatefulWidget {
  final LoyaltyTier? existing;
  const _TierDialog({this.existing});
  @override
  State<_TierDialog> createState() => _TierDialogState();
}

class _TierDialogState extends State<_TierDialog> {
  late final TextEditingController _name;
  late final TextEditingController _minSpend;
  late final TextEditingController _discount;
  String? _err;
  @override
  void initState(){
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _minSpend = TextEditingController(text: e?.minSpend.toString() ?? '0');
    _discount = TextEditingController(text: e?.discount.toString() ?? '0');
  }
  @override
  void dispose(){ _name.dispose(); _minSpend.dispose(); _discount.dispose(); super.dispose(); }

  void _submit(){
    final name = _name.text.trim();
    final minSpend = double.tryParse(_minSpend.text.trim());
    final disc = double.tryParse(_discount.text.trim());
    if(name.isEmpty){ setState(()=>_err='Name required'); return; }
    if(minSpend==null||minSpend<0){ setState(()=>_err='Min spend invalid'); return; }
    if(disc==null||disc<0||disc>100){ setState(()=>_err='Discount 0-100'); return; }
    Navigator.pop(context, LoyaltyTier(name: name, minSpend: minSpend, discount: disc));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texts = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(
        widget.existing==null? 'Add Tier' : 'Edit Tier',
        style: texts.titleMedium?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
      ),
      content: DefaultTextStyle(
        style: texts.bodyMedium?.copyWith(color: scheme.onSurface) ?? const TextStyle(),
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children:[
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Tier Name')),
              TextField(controller: _minSpend, decoration: const InputDecoration(labelText: 'Min Spend (₹)'), keyboardType: const TextInputType.numberWithOptions(decimal:true)),
              TextField(controller: _discount, decoration: const InputDecoration(labelText: 'Discount %'), keyboardType: const TextInputType.numberWithOptions(decimal:true)),
              if(_err!=null)
                Padding(
                  padding: const EdgeInsets.only(top:8),
                  child: Text(
                    _err!,
                    style: texts.labelSmall?.copyWith(color: scheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
