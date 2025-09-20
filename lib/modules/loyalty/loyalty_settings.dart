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
import 'package:flutter/services.dart';

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
  final FirebaseFirestore _fs;
  LoyaltySettingsRepository(this._fs);

  DocumentReference<Map<String, dynamic>> get _doc => _fs.collection('settings').doc('loyalty_config');

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

class LoyaltySettingsScreen extends StatefulWidget {
  const LoyaltySettingsScreen({super.key});
  @override
  State<LoyaltySettingsScreen> createState() => _LoyaltySettingsScreenState();
}

class _LoyaltySettingsScreenState extends State<LoyaltySettingsScreen> {
  final _repo = LoyaltySettingsRepository(FirebaseFirestore.instance);

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
    _load();
  }

  Future<void> _load() async {
    setState(()=> _loading = true);
    try {
      final s = await _repo.fetch();
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
      await _repo.save(_current!);
      _original = _current; // snapshot baseline
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Loyalty settings updated')));
    } catch(e){
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally { if(mounted) setState(()=> _saving = false); }
  }

  void _resetDefaults() async {
    final ok = await showDialog<bool>(context: context, builder: (_)=> AlertDialog(
      title: const Text('Reset to Defaults'),
      content: const Text('Revert all loyalty settings to default values? This does not affect existing customer documents.'),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(context,false), child: const Text('Cancel')),
        FilledButton(onPressed: ()=>Navigator.pop(context,true), child: const Text('Reset')),
      ],
    ));
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
        const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
        const SizedBox(height: 12),
        Text('Failed loading loyalty settings', style: Theme.of(context).textTheme.titleMedium),
        Padding(padding: const EdgeInsets.all(8), child: Text(_error!, textAlign: TextAlign.center)),
        FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
      ]));
    }

    final tiers = _current!.tiers;
    return LayoutBuilder(builder:(context, constraints){
      final wide = constraints.maxWidth > 980;
      return Scaffold(
        appBar: AppBar(title: const Text('Loyalty Settings'), actions:[
          TextButton.icon(onPressed: _resetDefaults, icon: const Icon(Icons.restore_outlined), label: const Text('Defaults')),
          const SizedBox(width:8),
        ]),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
                Wrap(spacing:16, runSpacing:16, children:[
                  SizedBox(width: wide ? 360 : double.infinity, child: _pointsRulesCard()),
                  Expanded(child: _tiersCard(tiers)),
                ]),
                const SizedBox(height: 20),
                _previewCard(tiers),
                const SizedBox(height: 120), // space for FAB region
              ]),
            ),
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        floatingActionButton: _saveFab(),
      );
    });
  }

  Widget _pointsRulesCard(){
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Row(children:[const Icon(Icons.tune), const SizedBox(width:8), Text('Points Rules', style: Theme.of(context).textTheme.titleMedium)]),
          const SizedBox(height: 16),
          TextField(
            controller: _pointsCtrl,
            decoration: InputDecoration(labelText: 'Points per ₹1', errorText: _pointsErr),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_){ _updateCurrentFromControllers(); _validateAll(); setState((){}); },
          ),
          const SizedBox(height: 12),
            TextField(
              controller: _minRedeemCtrl,
              decoration: InputDecoration(labelText: 'Minimum redeem points', errorText: _redeemErr),
              keyboardType: TextInputType.number,
              onChanged: (_){ _updateCurrentFromControllers(); _validateAll(); setState((){}); },
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _expiryCtrl,
            decoration: InputDecoration(labelText: 'Points expiry (months, blank = none)', errorText: _expiryErr),
            keyboardType: TextInputType.number,
            onChanged: (_){ _updateCurrentFromControllers(); _validateAll(); setState((){}); },
          ),
          if(_tiersErr!=null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_tiersErr!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          )
        ]),
      ),
    );
  }

  Widget _tiersCard(List<LoyaltyTier> tiers){
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Row(children:[const Icon(Icons.workspace_premium_outlined), const SizedBox(width:8), Text('Tiers', style: Theme.of(context).textTheme.titleMedium)]),
          const SizedBox(height: 12),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: tiers.length,
            onReorder: _reorder,
            itemBuilder: (_, i){
              final t = tiers[i];
              return ListTile(
                key: ValueKey('tier-$i-${t.name}'),
                leading: const Icon(Icons.drag_handle),
                title: Text('${t.name} • Min ₹${t.minSpend.toStringAsFixed(0)}'),
                subtitle: Text('Discount ${t.discount.toStringAsFixed(1)}%'),
                trailing: Wrap(spacing: 4, children:[
                  IconButton(tooltip:'Edit', icon: const Icon(Icons.edit_outlined), onPressed: ()=>_editTier(i)),
                  IconButton(tooltip:'Delete', icon: const Icon(Icons.delete_outline), onPressed: ()=>_deleteTier(i)),
                ]),
              );
            },
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(onPressed: _addTier, icon: const Icon(Icons.add), label: const Text('Add Tier')),
          ),
        ]),
      ),
    );
  }

  Widget _previewCard(List<LoyaltyTier> tiers){
    final spend = double.tryParse(_simSpendCtrl.text) ?? 0;
    final pts = (_current?.pointsPerCurrency ?? 0.01) * spend;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Row(children:[const Icon(Icons.visibility_outlined), const SizedBox(width:8), Text('Preview', style: Theme.of(context).textTheme.titleMedium)]),
          const SizedBox(height: 12),
          Row(children:[
            SizedBox(width:180, child: TextField(
              controller: _simSpendCtrl,
              decoration: const InputDecoration(labelText: 'Simulate spend (₹)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              onChanged: (_){ setState((){}); },
            )),
            const SizedBox(width: 16),
            Text('Earned points: ${((_current?.pointsPerCurrency ?? 0)* (double.tryParse(_simSpendCtrl.text) ?? 0)).toStringAsFixed(1)}'),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: [
            for(final t in tiers)
              _tierPreviewChip(t, spend, pts)
          ])
        ]),
      ),
    );
  }

  Widget _tierPreviewChip(LoyaltyTier t, double spend, double pts){
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
  color: Colors.grey.withValues(alpha: .05),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children:[
        Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height:4),
        Text('Min Spend ₹${t.minSpend.toStringAsFixed(0)}'),
        Text('Discount ${t.discount.toStringAsFixed(1)}%'),
        Text('Example discount on spend: ₹${(spend * (t.discount/100)).toStringAsFixed(2)}'),
      ]),
    );
  }

  Widget _saveFab(){
    final disabled = _saving || !_dirty || [_pointsErr,_redeemErr,_expiryErr,_tiersErr].any((e)=>e!=null);
    return FloatingActionButton.extended(
      onPressed: disabled ? null : _save,
      icon: _saving ? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2,color: Colors.white)) : const Icon(Icons.save_outlined),
      label: Text(_saving ? 'Saving...' : 'Save Changes'),
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
    return AlertDialog(
      title: Text(widget.existing==null? 'Add Tier' : 'Edit Tier'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children:[
        TextField(controller: _name, decoration: const InputDecoration(labelText: 'Tier Name')),
        TextField(controller: _minSpend, decoration: const InputDecoration(labelText: 'Min Spend (₹)'), keyboardType: const TextInputType.numberWithOptions(decimal:true)),
        TextField(controller: _discount, decoration: const InputDecoration(labelText: 'Discount %'), keyboardType: const TextInputType.numberWithOptions(decimal:true)),
        if(_err!=null) Padding(padding: const EdgeInsets.only(top:8), child: Text(_err!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
      ])),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}
