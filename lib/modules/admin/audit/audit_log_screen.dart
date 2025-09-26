import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/store_context_provider.dart';

class AuditLogEntry { final String id; final String action; final String user; final DateTime ts; final Map<String,dynamic> meta; AuditLogEntry(this.id,this.action,this.user,this.ts,this.meta); }

final auditLogFeedProvider = FutureProvider.family<List<AuditLogEntry>, String?>((ref, storeId) async {
  if (storeId == null) return [];
  await Future.delayed(const Duration(milliseconds: 120));
  return [AuditLogEntry('1','INVOICE_CREATE','alice', DateTime.now().subtract(const Duration(minutes:5)), {'invoice':'INV-1001'}), AuditLogEntry('2','PRODUCT_UPDATE','bob', DateTime.now().subtract(const Duration(hours:1)), {'sku':'SKU123'})];
});

class AuditLogScreen extends ConsumerStatefulWidget { const AuditLogScreen({super.key}); @override ConsumerState<AuditLogScreen> createState()=> _AuditLogScreenState(); }
class _AuditLogScreenState extends ConsumerState<AuditLogScreen>{
  String _filterAction='';
  @override Widget build(BuildContext context){
    final storeId = ref.watch(selectedStoreIdProvider);
    final logsAsync = ref.watch(auditLogFeedProvider(storeId));
    return Scaffold(appBar: AppBar(title: const Text('Audit Logs')), body: Column(children:[
      Padding(padding: const EdgeInsets.all(12), child: Row(children:[
        Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Filter action'), onChanged: (v)=> setState(()=> _filterAction=v.toUpperCase()))),
      ])),
      Expanded(child: logsAsync.when(
        data: (list){
          final filtered = list.where((e)=> e.action.contains(_filterAction)).toList();
          return ListView.separated(itemCount: filtered.length, separatorBuilder: (_,__)=>(const Divider(height:1)), itemBuilder: (_,i){
            final e = filtered[i];
            return ListTile(
              title: Text(e.action),
              subtitle: Text('${e.user} • ${e.ts}'),
              onTap: ()=> _openDetail(e),
            );
          });
        },
        error: (e,_)=> Center(child: Text('Error: $e')),
        loading: ()=> const Center(child: CircularProgressIndicator()),
      ))
    ]));
  }
  void _openDetail(AuditLogEntry e){
    showModalBottomSheet(context: context, builder: (_)=> SafeArea(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children:[
        Text(e.action, style: Theme.of(context).textTheme.titleLarge),
        Text('User: ${e.user}'),
        Text('Time: ${e.ts}'),
        const SizedBox(height:12),
        Text(e.meta.toString()),
        const SizedBox(height:12),
        FilledButton(onPressed: ()=> Navigator.pop(context), child: const Text('Close'))
      ]),
    )));
  }
}
