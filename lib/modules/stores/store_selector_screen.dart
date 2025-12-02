import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'providers.dart';
import '../../core/auth/auth_repository_and_provider.dart';
import '../../core/theme/theme_extension_helpers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class MyStoresScreen extends ConsumerWidget {
  const MyStoresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final storesAsync = ref.watch(myStoresProvider);
    final user = ref.watch(authStateProvider);
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              cs.surface,
              cs.primaryContainer.withOpacity(0.1),
            ],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(sizes.gapLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Modern Header with user info and logout
              Container(
                padding: EdgeInsets.all(sizes.gapMd),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [cs.primaryContainer.withOpacity(0.3), cs.primaryContainer.withOpacity(0.1)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: context.radiusMd,
                  border: Border.all(color: cs.primary.withOpacity(0.1)),
                ),
                child: Row(
                  children: [
                    // User Avatar
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [cs.primary, cs.primary.withOpacity(0.7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: context.radiusMd,
                        boxShadow: [
                          BoxShadow(
                            color: cs.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          ((user?.email ?? 'U').isNotEmpty ? (user?.email ?? 'U')[0] : 'U').toUpperCase(),
                          style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.bold, fontSize: sizes.fontLg),
                        ),
                      ),
                    ),
                    SizedBox(width: sizes.gapMd),
                    // Title and email
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('My Stores', style: TextStyle(fontSize: sizes.fontXl, fontWeight: FontWeight.bold, color: cs.onSurface)),
                          if ((user?.email ?? '').isNotEmpty)
                            Text(user!.email!, style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    // Create Store Button
                    FilledButton.icon(
                      onPressed: () => GoRouter.of(context).go('/stores/new'),
                      icon: Icon(Icons.add_business_rounded, size: sizes.iconSm),
                      label: const Text('Create Store'),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapMd),
                        shape: RoundedRectangleBorder(borderRadius: context.radiusSm),
                      ),
                    ),
                    SizedBox(width: sizes.gapMd),
                    // Logout Button
                    OutlinedButton.icon(
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                        if (context.mounted) {
                          GoRouter.of(context).go('/login');
                        }
                      },
                      icon: Icon(Icons.logout_rounded, size: sizes.iconSm, color: cs.error),
                      label: Text('Logout', style: TextStyle(color: cs.error)),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(horizontal: sizes.gapMd, vertical: sizes.gapMd),
                        shape: RoundedRectangleBorder(borderRadius: context.radiusSm),
                        side: BorderSide(color: cs.error.withOpacity(0.5)),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: sizes.gapSm),
              Padding(
                padding: EdgeInsets.only(left: sizes.gapXs),
                child: Text(
                  'Select a store to manage or create a new one',
                  style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurfaceVariant),
                ),
              ),
              if ((user?.email ?? '').isNotEmpty) ...[
                SizedBox(height: sizes.gapMd),
                _PendingInvites(email: user!.email!),
              ],
              SizedBox(height: sizes.gapMd),
              Expanded(
                child: storesAsync.when(
                  data: (items) {
                    if (items.isEmpty) {
                      return _EmptyState(onCreate: () => GoRouter.of(context).go('/stores/new'));
                    }
                    return ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final entry = items[index];
                        return _ModernStoreCard(entry: entry, ref: ref);
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
      ),
    );
  }
}

class _ModernStoreCard extends StatelessWidget {
  final StoreAccess entry;
  final WidgetRef ref;
  const _ModernStoreCard({required this.entry, required this.ref});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Container(
      margin: EdgeInsets.only(bottom: sizes.gapMd),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: context.radiusMd,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: context.radiusMd,
          onTap: () {
            ref.read(selectedStoreIdProvider.notifier).state = entry.store.id;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Selected store: ${entry.store.name}')),
            );
            GoRouter.of(context).go('/dashboard');
          },
          child: Padding(
            padding: EdgeInsets.all(sizes.gapMd),
            child: Row(
              children: [
                // Store Icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withOpacity(0.5),
                    borderRadius: context.radiusSm,
                  ),
                  child: Icon(Icons.storefront_rounded, color: cs.primary, size: sizes.iconLg),
                ),
                SizedBox(width: sizes.gapMd),
                // Store Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.store.name,
                        style: TextStyle(fontSize: sizes.fontMd, fontWeight: FontWeight.w600, color: cs.onSurface),
                      ),
                      SizedBox(height: sizes.gapXs),
                      Wrap(
                        spacing: sizes.gapXs,
                        runSpacing: sizes.gapXs,
                        children: [
                          _ModernChip(
                            icon: _getRoleIcon(entry.role),
                            label: entry.role,
                            color: cs.primary,
                          ),
                          if ((entry.store.slug ?? '').isNotEmpty)
                            _ModernChip(
                              icon: Icons.tag_rounded,
                              label: entry.store.slug!,
                              color: cs.secondary,
                            ),
                          _ModernChip(
                            icon: entry.store.status == 'active' ? Icons.check_circle_outline_rounded : Icons.pause_circle_outline_rounded,
                            label: entry.store.status,
                            color: entry.store.status == 'active' ? context.appColors.success : cs.outline,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Open Button
                FilledButton(
                  onPressed: () {
                    ref.read(selectedStoreIdProvider.notifier).state = entry.store.id;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Selected store: ${entry.store.name}')),
                    );
                    GoRouter.of(context).go('/dashboard');
                  },
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.symmetric(horizontal: sizes.gapLg, vertical: sizes.gapSm),
                    shape: RoundedRectangleBorder(borderRadius: context.radiusSm),
                  ),
                  child: const Text('Open'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getRoleIcon(String role) {
    switch (role) {
      case 'owner': return Icons.verified_user_rounded;
      case 'manager': return Icons.manage_accounts_rounded;
      case 'cashier': return Icons.point_of_sale_rounded;
      default: return Icons.visibility_rounded;
    }
  }
}

class _ModernChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _ModernChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final sizes = context.sizes;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: sizes.gapSm, vertical: sizes.gapXs),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(sizes.radiusSm),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: sizes.fontSm, color: color),
          SizedBox(width: sizes.gapXs),
          Text(label, style: TextStyle(fontSize: sizes.fontXs, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onCreate;
  const _EmptyState({required this.onCreate});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    return Center(
      child: Container(
        padding: EdgeInsets.all(sizes.gapXl),
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: context.radiusLg,
          border: Border.all(color: cs.outlineVariant.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [cs.primaryContainer, cs.primaryContainer.withOpacity(0.5)],
                ),
                borderRadius: context.radiusMd,
              ),
              child: Icon(Icons.storefront_rounded, size: sizes.iconXl, color: cs.primary),
            ),
            SizedBox(height: sizes.gapLg),
            Text(
              'No Stores Yet',
              style: TextStyle(fontSize: sizes.fontLg, fontWeight: FontWeight.bold, color: cs.onSurface),
            ),
            SizedBox(height: sizes.gapSm),
            Text(
              'You don\'t have access to any stores.\nCreate one or request an invite.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: sizes.fontSm, color: cs.onSurfaceVariant),
            ),
            SizedBox(height: sizes.gapLg),
            FilledButton.icon(
              onPressed: onCreate,
              icon: Icon(Icons.add_business_rounded, size: sizes.iconSm),
              label: const Text('Create New Store'),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: sizes.gapLg, vertical: sizes.gapMd),
                shape: RoundedRectangleBorder(borderRadius: context.radiusSm),
              ),
            ),
            SizedBox(height: sizes.gapMd),
            OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ask a store manager to invite you by email.')),
                );
              },
              icon: Icon(Icons.mail_outline_rounded, size: sizes.iconSm),
              label: const Text('Request Access'),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: sizes.gapLg, vertical: sizes.gapMd),
                shape: RoundedRectangleBorder(borderRadius: context.radiusSm),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingInvites extends ConsumerWidget {
  final String email;
  const _PendingInvites({required this.email});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final sizes = context.sizes;
    final q = FirebaseFirestore.instance
      .collection('invites')
      .where('email', isEqualTo: email)
      .where('status', isEqualTo: 'pending');
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator(minHeight: 2);
        }
        if (snap.hasError) return const SizedBox.shrink();
        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Container(
          padding: EdgeInsets.all(sizes.gapMd),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [context.appColors.warning.withOpacity(0.15), context.appColors.warning.withOpacity(0.1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: context.radiusMd,
            border: Border.all(color: context.appColors.warning.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(sizes.gapXs),
                    decoration: BoxDecoration(
                      color: context.appColors.warning.withOpacity(0.2),
                      borderRadius: context.radiusSm,
                    ),
                    child: Icon(Icons.mail_rounded, size: sizes.iconSm, color: context.appColors.warning),
                  ),
                  SizedBox(width: sizes.gapSm),
                  Text(
                    'You have ${docs.length} pending invitation${docs.length == 1 ? '' : 's'}',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: sizes.fontSm, color: cs.onSurface),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...docs.map((d) => _InviteTile(data: d.data(), docId: d.id)),
            ],
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
