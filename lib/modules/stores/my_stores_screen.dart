import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';
import '../../core/auth/auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class MyStoresScreen extends ConsumerWidget {
  const MyStoresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storesAsync = ref.watch(myStoresProvider);
    final user = ref.watch(authStateProvider);

    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('My Stores', style: Theme.of(context).textTheme.headlineSmall),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => GoRouter.of(context).go('/stores/new'),
                  icon: const Icon(Icons.add_business_outlined),
                  label: const Text('Create Store (no demo data)'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Create an empty store without demo data. You can add products, customers, and settings later.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if ((user?.email ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              _PendingInvites(email: user!.email!),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: storesAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return _EmptyState(onCreate: () => GoRouter.of(context).go('/stores/new'));
                  }
                  return ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 8),
                    itemBuilder: (context, index) {
                      final entry = items[index];
                      return ListTile(
                        leading: const Icon(Icons.store_outlined),
                        title: Text(entry.store.name),
                        subtitle: Row(children: [
                          _RoleChip(role: entry.role),
                          const SizedBox(width: 8),
                          if ((entry.store.slug ?? '').isNotEmpty)
                            Chip(label: Text(entry.store.slug!), visualDensity: VisualDensity.compact),
                          const SizedBox(width: 8),
                          Chip(label: Text(entry.store.status), visualDensity: VisualDensity.compact),
                        ]),
                        trailing: FilledButton(
                          onPressed: () {
                            ref.read(selectedStoreIdProvider.notifier).state = entry.store.id;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Selected store: ${entry.store.name}')),
                            );
                            // Navigate to dashboard after selecting a store
                            GoRouter.of(context).go('/dashboard');
                          },
                          child: const Text('Open'),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('Failed to load stores: $e')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  final String role;
  const _RoleChip({required this.role});
  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (role) {
      case 'owner':
        icon = Icons.verified_user_outlined; break;
      case 'manager':
        icon = Icons.manage_accounts_outlined; break;
      case 'cashier':
        icon = Icons.point_of_sale_outlined; break;
      default:
        icon = Icons.visibility_outlined; break;
    }
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(role),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.storefront_outlined, size: 48),
          const SizedBox(height: 12),
          const Text('You don\'t have access to any stores yet.'),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.add_business_outlined), label: const Text('Create a new store (no demo data)')),
              OutlinedButton.icon(onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ask a store manager to invite you by email.')),
                );
              }, icon: const Icon(Icons.mail_outline), label: const Text('Request access')),
            ],
          ),
        ],
      ),
    );
  }
}

class _PendingInvites extends ConsumerWidget {
  final String email;
  const _PendingInvites({required this.email});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
  final q = FirebaseFirestore.instance
    .collection('invites')
    .where('email', isEqualTo: email)
    .where('status', isEqualTo: 'pending'); // no orderBy to avoid requiring a composite index
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }
        if (snap.hasError) return const SizedBox.shrink();
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.mail_outline),
                    const SizedBox(width: 8),
                    Text('You have ${docs.length} store invitation${docs.length == 1 ? '' : 's'}'),
                  ],
                ),
                const SizedBox(height: 8),
                ...docs.map((d) => _InviteTile(data: d.data(), docId: d.id)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InviteTile extends ConsumerWidget {
  final Map<String, dynamic> data;
  final String docId;
  const _InviteTile({required this.data, required this.docId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storeId = (data['storeId'] ?? '') as String;
    final role = (data['role'] ?? 'viewer') as String;
    final storeName = (data['storeName'] ?? storeId) as String;
    return ListTile(
      dense: true,
      leading: const Icon(Icons.store_outlined),
      title: Text(storeName),
      subtitle: Text('Role: $role'),
      trailing: Wrap(spacing: 8, children: [
        TextButton(
          onPressed: () async {
            try {
              // Pin region to deployed location to avoid cross-region callable errors
              final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('acceptInvite');
              final result = await callable.call({'inviteId': docId});
              final data = (result.data as Map?) ?? {};
              final newStoreId = (data['storeId'] ?? storeId) as String;
              // Select the store
              ref.read(selectedStoreIdProvider.notifier).state = newStoreId;
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Joined $storeName')));
                // After accepting an invite, jump into the app immediately
                GoRouter.of(context).go('/dashboard');
              }
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to accept: $e')));
            }
          },
          child: const Text('Accept'),
        ),
        OutlinedButton(
          onPressed: () async {
            try {
              // Pin region to deployed location to avoid cross-region callable errors
              final callable = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('declineInvite');
              await callable.call({'inviteId': docId});
            } catch (e) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to decline: $e')));
            }
          },
          child: const Text('Decline'),
        ),
      ]),
    );
  }
}
