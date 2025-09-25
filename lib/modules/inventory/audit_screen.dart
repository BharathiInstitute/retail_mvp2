import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth.dart';
import 'inventory_repository.dart';
import 'csv_utils.dart';
import 'download_helper_stub.dart' if (dart.library.html) 'download_helper_web.dart';
import 'import_products_screen.dart' show ImportProductsScreen;
import 'inventory.dart'; // access shared providers
import 'inventory_repository.dart' show ProductDoc; // product model

// Public copy of active filter enum (was private in inventory.dart)
enum ActiveFilter { all, active, inactive }

class _AuditMeta {
  final DateTime updatedAt;
  final String updatedBy;
  _AuditMeta(this.updatedAt, this.updatedBy);
}

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key});
  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  final Map<String,int> _storeOverrides = {};
  final Map<String,int> _whOverrides = {};
  final Map<String,String> _noteOverrides = {};
  final Map<String,_AuditMeta> _overrideMeta = {}; // tracks last update timestamp + user
  String _search = '';
  ActiveFilter _activeFilter = ActiveFilter.all;
  int _gstFilter = -1;

  String _fmtDateTime(DateTime d){
    return '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }

  @override
  void dispose() { super.dispose(); }

  List<ProductDoc> _applyFilters(List<ProductDoc> src){
    Iterable<ProductDoc> it = src;
    final q = _search.trim().toLowerCase();
    if(q.isNotEmpty){
      it = it.where((p)=> p.sku.toLowerCase().contains(q) || p.name.toLowerCase().contains(q) || p.barcode.toLowerCase().contains(q));
    }
    if(_activeFilter!=ActiveFilter.all){
      final want = _activeFilter == ActiveFilter.active; it = it.where((p)=>p.isActive==want);
    }
    if(_gstFilter!=-1){ it = it.where((p)=>(p.taxPct??0)==_gstFilter); }
    return it.toList();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(productsStreamProvider);
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
        Row(children:[
          Transform.translate(
            offset: const Offset(0,-4),
            child: SizedBox(
              width: 260,
              child: TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search),labelText:'Search SKU/Name/Barcode',isDense:true,contentPadding: EdgeInsets.symmetric(horizontal:12,vertical:8)),
                onChanged:(v)=>setState(()=>_search=v),
              ),
            ),
          ),
          const SizedBox(width:16),
          Transform.translate(
            offset: const Offset(0,-4),
            child: DropdownButton<ActiveFilter>(
              value: _activeFilter,
              onChanged:(v)=>setState(()=>_activeFilter=v??ActiveFilter.all),
              items: const [
                DropdownMenuItem(value:ActiveFilter.all, child: Text('All')),
                DropdownMenuItem(value:ActiveFilter.active, child: Text('Active')),
                DropdownMenuItem(value:ActiveFilter.inactive, child: Text('Inactive')),
              ],
            ),
          ),
          const SizedBox(width:16),
          Transform.translate(
            offset: const Offset(0,-4),
            child: DropdownButton<int>(
              value: _gstFilter,
              onChanged:(v)=>setState(()=>_gstFilter=v??-1),
              items: const [
                DropdownMenuItem(value:-1, child: Text('GST: All')),
                DropdownMenuItem(value:0, child: Text('GST 0%')),
                DropdownMenuItem(value:5, child: Text('GST 5%')),
                DropdownMenuItem(value:12, child: Text('GST 12%')),
                DropdownMenuItem(value:18, child: Text('GST 18%')),
              ],
            ),
          ),
          const Spacer(),
          Builder(builder: (context){
            final user = ref.watch(authStateProvider); final isSignedIn = user!=null;
            return Row(mainAxisSize: MainAxisSize.min, children:[
              // Minimal inline add product trigger removed (using import screen only)
              const SizedBox(width:8),
              OutlinedButton.icon(onPressed: ()=>_exportCsv(), icon: const Icon(Icons.file_download_outlined), label: const Text('Export CSV')),
              const SizedBox(width:8),
              OutlinedButton.icon(
                onPressed: isSignedIn ? ()=> Navigator.of(context).push(MaterialPageRoute(builder: (_)=> const ImportProductsScreen()))
                                     : ()=> ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please sign in to import products.'))),
                icon: const Icon(Icons.file_upload_outlined), label: const Text('Import CSV'),
              ),
            ]);
          })
        ]),
        const SizedBox(height:8),
        Padding(
          padding: const EdgeInsets.only(bottom:4.0),
          child: Text('Tip: Click any row to edit stock counts & add a note.', style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(
          child: Card(
            child: async.when(
              data:(products){
                if(products.isEmpty){ return const Center(child: Text('No products available.')); }
                final filtered = _applyFilters(products);
                if(filtered.isEmpty){ return const Center(child: Text('No products match filters.')); }
                return LayoutBuilder(builder:(context,constraints){
                  final table = DataTable(
                    columnSpacing:32,
                    headingRowHeight:40,
                    dataRowMinHeight:38,
                    dataRowMaxHeight:44,
                    showCheckboxColumn: false,
                    columns: const [
                      DataColumn(label: Text('SKU')),
                      DataColumn(label: Text('Name')),
                      DataColumn(label: Text('Barcode')),
                      DataColumn(label: Text('Unit Price'), numeric: true),
                      DataColumn(label: Text('GST %'), numeric: true),
                      DataColumn(label: Text('Store'), numeric: true),
                      DataColumn(label: Text('Warehouse'), numeric: true),
                      DataColumn(label: Text('Total'), numeric: true),
                      DataColumn(label: Text('Updated Date')),
                      DataColumn(label: Text('Updated By')),
                      DataColumn(label: Text('Note')),
                    ],
                    rows:[
                      for(final p in filtered) DataRow(
                        onSelectChanged: (_)=> _openEditDialog(p),
                        cells: [
                          DataCell(Text(p.sku)),
                          DataCell(Text(p.name)),
                          DataCell(Text(p.barcode)),
                          DataCell(Align(alignment: Alignment.centerRight, child: Text('₹${p.unitPrice.toStringAsFixed(2)}'))),
                          DataCell(Align(alignment: Alignment.centerRight, child: Text((p.taxPct ?? 0).toString()))),
                          DataCell(_stockCell(p, isStore: true)),
                          DataCell(_stockCell(p, isStore: false)),
                          DataCell(Align(alignment: Alignment.centerRight, child: Text((( _storeOverrides[p.sku] ?? p.stockAt('Store')) + (_whOverrides[p.sku] ?? p.stockAt('Warehouse')) ).toString()))),
                          DataCell(Text(
                            _overrideMeta[p.sku] != null
                              ? _fmtDateTime(_overrideMeta[p.sku]!.updatedAt)
                              : (p.updatedAt != null ? _fmtDateTime(p.updatedAt!) : '-')
                          )),
                          DataCell(Text(
                            _overrideMeta[p.sku]?.updatedBy ?? (p.updatedBy ?? '-')
                          )),
                          DataCell(SizedBox(width:220, child: Text(_noteOverrides[p.sku] ?? p.auditNote ?? '-', maxLines:2, overflow: TextOverflow.ellipsis))),
                        ],
                      ),
                    ],
                  );
                  return SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(constraints: BoxConstraints(minWidth: constraints.maxWidth), child: table),
                    ),
                  );
                });
              },
              error:(e,st)=> Center(child: Text('Error: $e')),
              loading: ()=> const Center(child: CircularProgressIndicator()),
            ),
          ),
        ),
        const SizedBox(height:8),
        Text('Changes here are LOCAL audit overrides. They do NOT modify the product master data.', style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }

  Widget _stockCell(ProductDoc p, {required bool isStore}){
    final overrides = isStore ? _storeOverrides : _whOverrides;
    final value = overrides[p.sku] ?? p.stockAt(isStore ? 'Store' : 'Warehouse');
    return GestureDetector(
      onTap: ()=> _openEditDialog(p),
      child: Align(alignment: Alignment.centerRight, child: Text(value.toString())),
    );
  }

  Future<void> _openEditDialog(ProductDoc p) async {
    final result = await showDialog<_AuditEditResult>(
      context: context,
      builder: (_) => _AuditEditDialog(
        sku: p.sku,
        store: _storeOverrides[p.sku] ?? p.stockAt('Store'),
        warehouse: _whOverrides[p.sku] ?? p.stockAt('Warehouse'),
        note: _noteOverrides[p.sku] ?? p.auditNote,
      ),
    );
    if(result == null) return;
    final user = ref.read(authStateProvider);
    final origStore = p.stockAt('Store');
    final origWh = p.stockAt('Warehouse');
    setState(() {
      if(result.store == origStore){ _storeOverrides.remove(p.sku);} else {_storeOverrides[p.sku]=result.store;}
      if(result.warehouse == origWh){ _whOverrides.remove(p.sku);} else {_whOverrides[p.sku]=result.warehouse;}
      if(result.note == null || result.note!.trim().isEmpty){ _noteOverrides.remove(p.sku);} else { _noteOverrides[p.sku]=result.note!.trim(); }
      final changed = (result.store!=origStore) || (result.warehouse!=origWh) || (result.note != (p.auditNote ?? ''));
      if(changed){
        final by = (user?.email?.isNotEmpty ?? false) ? user!.email! : (user?.uid ?? 'local');
        _overrideMeta[p.sku] = _AuditMeta(DateTime.now(), by);
      } else {
        _overrideMeta.remove(p.sku);
      }
    });
    try{
      if(user != null){
        await ref.read(inventoryRepoProvider).auditUpdateStock(
          sku: p.sku,
          storeQty: result.store,
          warehouseQty: result.warehouse,
          updatedBy: user.email ?? user.uid,
          note: result.note?.trim().isEmpty ?? true ? null : result.note!.trim(),
        );
      }
    }catch(e){
      if(mounted){
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update: $e')));
      }
    }
  }

  void _exportCsv(){
    final products = ref.read(productsStreamProvider).maybeWhen(data:(d)=>d, orElse: ()=> <ProductDoc>[]);
    final filtered = _applyFilters(products);
    final rows = <List<String>>[];
    rows.add(['SKU','Name','Barcode','UnitPrice','GST','Store','Warehouse','Total','StoreOverridden','WarehouseOverridden','UpdatedDate','UpdatedBy','Note']);
    for(final p in filtered){
      final store = _storeOverrides[p.sku] ?? p.stockAt('Store');
      final wh = _whOverrides[p.sku] ?? p.stockAt('Warehouse');
      final meta = _overrideMeta[p.sku];
      final docDate = p.updatedAt;
      final docBy = p.updatedBy;
      final note = _noteOverrides[p.sku] ?? p.auditNote ?? '';
      rows.add([
        p.sku,p.name,p.barcode,p.unitPrice.toStringAsFixed(2),(p.taxPct??0).toString(),store.toString(),wh.toString(),(store+wh).toString(),(_storeOverrides.containsKey(p.sku)).toString(),(_whOverrides.containsKey(p.sku)).toString(),
        meta != null ? _fmtDateTime(meta.updatedAt) : (docDate!=null ? _fmtDateTime(docDate) : ''),
        meta?.updatedBy ?? (docBy ?? ''),
        note,
      ]);
    }
    final csv = CsvUtils.listToCsv(rows); final bytes = Uint8List.fromList(csv.codeUnits); downloadBytes(bytes,'audit_export.csv','text/csv');
  }
}

class _AuditEditResult {
  final int store;
  final int warehouse;
  final String? note;
  _AuditEditResult({required this.store, required this.warehouse, this.note});
}

class _AuditEditDialog extends StatefulWidget {
  final String sku; final int store; final int warehouse; final String? note;
  const _AuditEditDialog({required this.sku, required this.store, required this.warehouse, this.note});
  @override State<_AuditEditDialog> createState()=>_AuditEditDialogState();
}

class _AuditEditDialogState extends State<_AuditEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _store;
  late final TextEditingController _wh;
  late final TextEditingController _note;

  @override void initState(){
    super.initState();
    _store = TextEditingController(text: widget.store.toString());
    _wh = TextEditingController(text: widget.warehouse.toString());
    _note = TextEditingController(text: widget.note ?? '');
  }
  @override void dispose(){ _store.dispose(); _wh.dispose(); _note.dispose(); super.dispose(); }

  @override Widget build(BuildContext context){
    return AlertDialog(
      title: Text('Audit ${widget.sku}'),
      content: Form(
        key: _formKey,
        child: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children:[
                  Expanded(child: TextFormField(
                    controller: _store,
                    decoration: const InputDecoration(labelText:'Store Qty'),
                    keyboardType: TextInputType.number,
                    validator:(v){ final n=int.tryParse(v??''); if(n==null||n<0) return 'Enter >=0'; return null; },
                  )),
                  const SizedBox(width:12),
                  Expanded(child: TextFormField(
                    controller: _wh,
                    decoration: const InputDecoration(labelText:'Warehouse Qty'),
                    keyboardType: TextInputType.number,
                    validator:(v){ final n=int.tryParse(v??''); if(n==null||n<0) return 'Enter >=0'; return null; },
                  )),
                ]),
                const SizedBox(height:12),
                TextFormField(
                  controller: _note,
                  decoration: const InputDecoration(labelText:'Note (optional)'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: ()=>Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: (){
            if(!(_formKey.currentState?.validate()??false)) return;
            final store = int.parse(_store.text.trim());
            final wh = int.parse(_wh.text.trim());
            Navigator.pop(context, _AuditEditResult(store: store, warehouse: wh, note: _note.text.trim().isEmpty ? null : _note.text.trim()));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
