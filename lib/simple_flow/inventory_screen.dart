import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class InventoryLiveScreen extends StatelessWidget {
  const InventoryLiveScreen({super.key});

  Stream<QuerySnapshot<Map<String,dynamic>>> _stream() => FirebaseFirestore.instance
      .collection('products')
      .orderBy('name')
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inventory')),
      body: StreamBuilder<QuerySnapshot<Map<String,dynamic>>>(
        stream: _stream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No products yet'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final d = docs[i];
              final data = d.data();
              return ListTile(
                title: Text(data['name'] ?? ''),
                trailing: Text('Stock: ${data['stock'] ?? 0}'),
                subtitle: data['sku'] != null ? Text('SKU: ${data['sku']}') : null,
              );
            },
          );
        },
      ),
    );
  }
}
