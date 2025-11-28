import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../stores/providers.dart';

class CategoryScreen extends ConsumerStatefulWidget {
  const CategoryScreen({super.key});

  @override
  ConsumerState<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends ConsumerState<CategoryScreen> {
  final _categoryCtrl = TextEditingController();
  final Map<String, _Cat> _catsById = <String, _Cat>{};
  bool _loading = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  @override
  void dispose() {
    _sub?.cancel();
    _categoryCtrl.dispose();
    super.dispose();
  }

  CollectionReference<Map<String, dynamic>> _catsCol(String storeId) => FirebaseFirestore.instance
      .collection('stores')
      .doc(storeId)
      .collection('categories');

  Future<void> _startListen(String storeId) async {
    await _sub?.cancel();
    setState(() => _loading = true);
    _sub = _catsCol(storeId).orderBy('name').snapshots().listen((snap) {
      final next = <String, _Cat>{};
      for (final d in snap.docs) {
        final data = d.data();
        next[d.id] = _Cat(
          name: (data['name'] ?? '') as String,
          subs: List<String>.from((data['subcategories'] ?? const <dynamic>[]) as List<dynamic>),
        );
      }
      if (mounted) {
        setState(() {
          _catsById
            ..clear()
            ..addAll(next);
          _loading = false;
        });
      }
    });
  }

  Future<void> _ensureListening() async {
    final sid = ref.read(selectedStoreIdProvider);
    if (sid == null || sid.isEmpty) return;
    if (_sub == null) {
      await _startListen(sid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(builder: (context) {
              final sid = ref.watch(selectedStoreIdProvider);
              // Start listening when we have a storeId
              if (sid != null && sid.isNotEmpty) {
                // fire and forget
                _ensureListening();
              }
              return SizedBox.shrink();
            }),
            // Category section
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _categoryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Add Category',
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () async {
                    final sid = ref.read(selectedStoreIdProvider);
                    final cat = _categoryCtrl.text.trim();
                    if (cat.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Enter a category name')),
                      );
                      return;
                    }
                    if (sid == null || sid.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Select a store first')),
                      );
                      return;
                    }
                    try {
                      await _catsCol(sid).add({'name': cat, 'subcategories': <String>[]});
                      _categoryCtrl.clear();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to add: $e')),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Align(alignment: Alignment.topLeft, child: Padding(padding: EdgeInsets.only(top: 12), child: CircularProgressIndicator()))
                  : _catsById.isEmpty
                  ? Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        'No categories yet. Add and they will appear here.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    )
                  : ListView.separated(
                      itemCount: _catsById.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final id = _catsById.keys.elementAt(i);
                        final cat = _catsById[id]!;
                        final subs = cat.subs;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(cat.name, style: Theme.of(context).textTheme.titleSmall)),
                                IconButton(
                                  tooltip: 'Add Sub Category',
                                  icon: const Icon(Icons.add_circle_outline),
                                  onPressed: () async {
                                    final text = await _promptText(context, 'Add sub category');
                                    if (text == null || text.trim().isEmpty) return;
                                    final sid = ref.read(selectedStoreIdProvider);
                                    if (sid == null || sid.isEmpty) return;
                                    try {
                                      await _catsCol(sid)
                                          .doc(id)
                                          .update({'subcategories': FieldValue.arrayUnion([text.trim()])});
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to add sub: $e')),
                                      );
                                    }
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Edit Category',
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () async {
                                    final text = await _promptText(context, 'Edit category', initial: cat.name);
                                    if (text == null || text.trim().isEmpty || text.trim() == cat.name) return;
                                    final sid = ref.read(selectedStoreIdProvider);
                                    if (sid == null || sid.isEmpty) return;
                                    try {
                                      await _catsCol(sid).doc(id).update({'name': text.trim()});
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to update: $e')),
                                      );
                                    }
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Delete Category',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    final sid = ref.read(selectedStoreIdProvider);
                                    if (sid == null || sid.isEmpty) return;
                                    try {
                                      await _catsCol(sid).doc(id).delete();
                                    } catch (e) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to delete: $e')),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                            if (subs.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(left: 8.0, bottom: 8.0),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: subs
                                      .map((s) => Chip(
                                            label: Text(s),
                                            onDeleted: () async {
                                              final sid = ref.read(selectedStoreIdProvider);
                                              if (sid == null || sid.isEmpty) return;
                                              try {
                                                await _catsCol(sid)
                                                    .doc(id)
                                                    .update({'subcategories': FieldValue.arrayRemove([s])});
                                              } catch (e) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(content: Text('Failed to remove: $e')),
                                                );
                                              }
                                            },
                                          ))
                                      .toList(),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
            // Removed legacy standalone Sub Category input; use + on each category row
          ],
        ),
      ),
    );
  }

  Future<String?> _promptText(BuildContext context, String title, {String? initial}) async {
    final ctrl = TextEditingController(text: initial ?? '');
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Enter text'),
          onSubmitted: (v) => Navigator.of(dialogCtx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogCtx).pop(ctrl.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _Cat {
  _Cat({required this.name, required this.subs});
  String name;
  List<String> subs;
}
