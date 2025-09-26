import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/store_context_provider.dart';
import '../providers/capabilities_provider.dart';

class StoreSettingsScreen extends ConsumerStatefulWidget {
  const StoreSettingsScreen({super.key});
  @override ConsumerState<StoreSettingsScreen> createState()=> _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends ConsumerState<StoreSettingsScreen> with TickerProviderStateMixin {
  late TabController _tab;
  Map<String,dynamic> form = { 'general': {}, 'tax': { 'rates': [] }, 'templates': [], 'policies': { 'returnDays': 7, 'maxDiscountPct': 20 } };
  Map<String,dynamic> original = {};
  bool saving=false;

  @override void initState(){ super.initState(); _tab = TabController(length: 4, vsync: this); original = jsonDecode(jsonEncode(form)); }
  bool get dirty => jsonEncode(form) != jsonEncode(original);

  @override Widget build(BuildContext context){
    final caps = ref.watch(capabilitiesProvider);
    final readOnly = !caps.editSettings;
    return Scaffold(
      appBar: AppBar(title: const Text('Store Settings'), bottom: TabBar(controller: _tab, tabs: const [
        Tab(text: 'General'), Tab(text: 'Tax Rates'), Tab(text: 'Templates'), Tab(text: 'Policies')
      ]), actions: [
        if (dirty) TextButton(onPressed: saving? null: _previewDiff, child: const Text('Review Changes')),
      ]),
      body: TabBarView(controller: _tab, children: [
        _GeneralTab(data: form['general'], readOnly: readOnly, onChanged: (m){ setState(()=> form['general']=m); }),
        _TaxTab(data: form['tax'], readOnly: readOnly, onChanged: (m){ setState(()=> form['tax']=m); }),
        _TemplatesTab(list: form['templates'], readOnly: readOnly, onChanged: (l){ setState(()=> form['templates']=l); }),
        _PoliciesTab(data: form['policies'], readOnly: readOnly, onChanged: (m){ setState(()=> form['policies']=m); }),
      ])
    );
  }

  void _previewDiff(){
    final diff = <String, dynamic>{};
    void walk(String path, dynamic a, dynamic b){
      if (a is Map && b is Map){
        for (final k in {...a.keys, ...b.keys}){ walk('$path/$k', a[k], b[k]); }
      } else if (a is List && b is List){
        if (jsonEncode(a)!=jsonEncode(b)) diff[path] = { 'from': a, 'to': b };
      } else {
        if ('$a' != '$b') diff[path] = { 'from': a, 'to': b };
      }
    }
    walk('', original, form);
    showDialog(context: context, builder: (_)=> AlertDialog(
      title: const Text('Change Preview'),
      content: SizedBox(width: 480, child: diff.isEmpty? const Text('No changes'): ListView(
        children: diff.entries.map((e)=> ListTile(title: Text(e.key.isEmpty? '/': e.key), subtitle: Text('${e.value['from']} → ${e.value['to']}'))).toList(),
      )),
      actions: [TextButton(onPressed: ()=> Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: saving? null: _apply, child: saving? const SizedBox(width:16,height:16,child:CircularProgressIndicator(strokeWidth:2)) : const Text('Apply'))],
    ));
  }

  Future<void> _apply() async {
    setState(()=> saving=true);
    await Future.delayed(const Duration(milliseconds: 600)); // mock write
    original = jsonDecode(jsonEncode(form));
    if (mounted){ setState(()=> saving=false); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings saved'))); }
  }
}

class _GeneralTab extends StatelessWidget {
  final Map data; final bool readOnly; final ValueChanged<Map> onChanged; const _GeneralTab({required this.data, required this.readOnly, required this.onChanged});
  @override Widget build(BuildContext context){
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(enabled: !readOnly, decoration: const InputDecoration(labelText: 'Store Name'), onChanged: (v)=> onChanged({...data,'name': v})),
      TextField(enabled: !readOnly, decoration: const InputDecoration(labelText: 'GSTIN'), onChanged: (v)=> onChanged({...data,'gstin': v})),
    ]);
  }
}
class _TaxTab extends StatefulWidget { final Map data; final bool readOnly; final ValueChanged<Map> onChanged; const _TaxTab({required this.data, required this.readOnly, required this.onChanged}); @override State<_TaxTab> createState()=> _TaxTabState(); }
class _TaxTabState extends State<_TaxTab>{
  List<Map<String,dynamic>> get rates => List<Map<String,dynamic>>.from(widget.data['rates'] as List);
  void _add(){ final r=[...rates, {'label':'GST 5%','rate':0.05}]; widget.onChanged({...widget.data,'rates': r}); }
  @override Widget build(BuildContext ctx){
    return Column(children:[
      Expanded(child: ListView(children:[
        for (int i=0;i<rates.length;i++) ListTile(
          title: TextField(enabled: !widget.readOnly, controller: TextEditingController(text: rates[i]['label']), onChanged: (v){ rates[i]['label']=v; widget.onChanged({...widget.data,'rates': rates}); }, decoration: const InputDecoration(labelText: 'Label')), 
          trailing: SizedBox(width:120, child: TextField(enabled: !widget.readOnly, controller: TextEditingController(text: rates[i]['rate'].toString()), onChanged: (v){ final d = double.tryParse(v)??0; rates[i]['rate']=d; widget.onChanged({...widget.data,'rates': rates}); }, decoration: const InputDecoration(labelText: 'Rate', suffixText: '%'))),
        ),
      ])),
      if (!widget.readOnly) Padding(padding: const EdgeInsets.all(12), child: FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Add Rate')))
    ]);
  }
}
class _TemplatesTab extends StatelessWidget { final List list; final bool readOnly; final ValueChanged<List> onChanged; const _TemplatesTab({required this.list, required this.readOnly, required this.onChanged}); @override Widget build(BuildContext context){
  return ListView(padding: const EdgeInsets.all(16), children: [
    for (int i=0;i<list.length;i++) Card(child: ListTile(title: Text(list[i]['name']??'Template $i'), subtitle: Text(list[i].toString()))),
    if (!readOnly) FilledButton.icon(onPressed: (){ onChanged([...list, {'name':'New Template','active': false}]); }, icon: const Icon(Icons.add), label: const Text('Add Template'))
  ]);
}}
class _PoliciesTab extends StatelessWidget { final Map data; final bool readOnly; final ValueChanged<Map> onChanged; const _PoliciesTab({required this.data, required this.readOnly, required this.onChanged}); @override Widget build(BuildContext context){
  final returnDays = data['returnDays']??7; final maxDiscount = data['maxDiscountPct']??20;
  return ListView(padding: const EdgeInsets.all(16), children:[
    TextField(enabled: !readOnly, decoration: const InputDecoration(labelText: 'Return Days'), controller: TextEditingController(text: returnDays.toString()), onChanged: (v)=> onChanged({...data,'returnDays': int.tryParse(v)??returnDays})),
    TextField(enabled: !readOnly, decoration: const InputDecoration(labelText: 'Max Discount %'), controller: TextEditingController(text: maxDiscount.toString()), onChanged: (v)=> onChanged({...data,'maxDiscountPct': int.tryParse(v)??maxDiscount})),
  ]);
 }}
