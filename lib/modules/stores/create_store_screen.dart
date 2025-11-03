import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../core/auth/auth.dart';
import 'providers.dart';

class CreateStoreScreen extends ConsumerStatefulWidget {
  const CreateStoreScreen({super.key});

  @override
  ConsumerState<CreateStoreScreen> createState() => _CreateStoreScreenState();
}

class _CreateStoreScreenState extends ConsumerState<CreateStoreScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  static String _slugify(String input) => input
    .toLowerCase()
    .replaceAll(RegExp(r"[^a-z0-9]+"), '-')
    .replaceAll(RegExp(r"(^-+|-+$)"), '');

  Future<void> _create() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final user = ref.read(authStateProvider);
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login first')));
      return;
    }
    setState(() => _busy = true);
    try {
      final name = _nameCtrl.text.trim();
      final slug = _slugify(name);
  // Explicitly target the deployed region to avoid cross-region callable issues
  final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('createStore');
  final result = await callable.call({'name': name, 'slug': slug, 'seed': 'empty'});
      final data = (result.data as Map?) ?? {};
      final storeId = (data['storeId'] ?? '') as String;
      if (storeId.isEmpty) throw 'createStore returned no storeId';

      ref.read(selectedStoreIdProvider.notifier).state = storeId;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Store created: $name')));
        // Go straight into the app shell now that a store exists
        GoRouter.of(context).go('/dashboard');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to create store: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Create a new store', style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 6),
                    Text(
                      'This will create an empty store (no demo data). You can configure settings and add items later.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Store name', prefixIcon: Icon(Icons.store_outlined)),
                      textInputAction: TextInputAction.done,
                      validator: (v) => (v == null || v.trim().length < 3) ? 'Enter at least 3 characters' : null,
                      onFieldSubmitted: (_) => _create(),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: _busy ? null : () => GoRouter.of(context).go('/stores'), child: const Text('Cancel')),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: _busy ? null : _create,
                          icon: _busy ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.add),
                          label: const Text('Create (no demo data)'),
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
