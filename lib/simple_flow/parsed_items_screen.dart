import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import 'inventory_screen.dart';

class ParsedItemsScreen extends StatefulWidget {
  final List<Map<String,dynamic>> items;
  const ParsedItemsScreen({super.key, required this.items});
  @override
  State<ParsedItemsScreen> createState() => _ParsedItemsScreenState();
}

class _ParsedItemsScreenState extends State<ParsedItemsScreen> {
  bool _updating = false;
  String? _error;
  List<Map<String,dynamic>> get _items => widget.items;

  Future<void> _apply() async {
    setState(() { _updating = true; _error = null; });
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('applyInvoiceStockSimple');
      await callable.call({'items': _items});
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const InventoryLiveScreen()));
    } on FirebaseFunctionsException catch (e) {
      setState(() { _error = e.message; });
    } catch (e) {
      setState(() { _error = e.toString(); });
    } finally {
      if (mounted) setState(() { _updating = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parsed Items')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _items.isNotEmpty && !_updating ? _apply : null,
        icon: const Icon(Icons.sync), label: const Text('Match & Update'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final it = _items[i];
                  return ListTile(
                    leading: CircleAvatar(child: Text('${i+1}')),
                    title: Text(it['name'] ?? ''),
                    trailing: Text('Qty: ${it['qty']}'),
                  );
                },
              ),
            ),
            if (_updating) const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()),
            if (_error != null) Padding(
              padding: const EdgeInsets.all(12.0),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            )
          ],
        ),
      ),
    );
  }
}
