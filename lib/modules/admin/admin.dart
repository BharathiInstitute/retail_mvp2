// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminModuleScreen extends StatefulWidget {
	const AdminModuleScreen({super.key});
	@override
	State<AdminModuleScreen> createState() => _AdminModuleScreenState();
}

class _AdminModuleScreenState extends State<AdminModuleScreen> {
	final List<_SettingItem> _settings = [
		_SettingItem(icon: Icons.storefront_outlined, title: 'Store Info', subtitle: 'Name, address, GSTIN'),
		_SettingItem(icon: Icons.group_outlined, title: 'Users & Roles', subtitle: 'Manage staff access'),
		_SettingItem(icon: Icons.qr_code_2_outlined, title: 'POS Settings', subtitle: 'Receipts, payment modes'),
		_SettingItem(icon: Icons.cloud_outlined, title: 'Cloud Backup', subtitle: 'Automatic backups to cloud'),
		_SettingItem(icon: Icons.policy_outlined, title: 'Policies', subtitle: 'Returns, exchange, discounts'),
	];

	String _search = '';
	bool _showUsers = true;
	bool _authReady = false;
	String? _authError;

	@override
	void initState() {
		super.initState();
		_ensureAuthed();
	}

	Future<void> _ensureAuthed() async {
		setState(() { _authReady = false; _authError = null; });
		try {
			final auth = FirebaseAuth.instance;
			if (auth.currentUser == null) {
				await auth.signInAnonymously();
			}
			final user = auth.currentUser;
			if (user == null) throw Exception('No user after sign-in');
			final uid = user.uid;
			final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
			final snap = await userRef.get();
			if (!snap.exists) {
				// Do NOT set 'role' on initial create; rules forbid privilege fields during self creation
				try {
					await userRef.set({
						'email': user.email ?? '',
						'createdAt': FieldValue.serverTimestamp(),
						'updatedAt': FieldValue.serverTimestamp(),
					}, SetOptions(merge: true));
				} catch (e) {
					// If this still fails, capture error and surface later
					if (mounted) setState(() { _authError = 'Create user doc failed: $e'; });
				}
			}
			if (mounted) setState(() => _authReady = true);
		} catch (e) {
			if (mounted) setState(() { _authError = e.toString(); _authReady = true; });
		}
	}

	Stream<List<_UserEntry>> _userStream() {
		return FirebaseFirestore.instance.collection('users').snapshots().map((snap) => snap.docs.map((d) {
			final data = d.data();
			return _UserEntry(
				uid: d.id,
				email: data['email'] ?? '',
				isAdmin: data['role'] == 'admin' || data['admin'] == true || (data['claims']?['admin'] == true),
				role: data['role'] ?? (data['admin'] == true ? 'admin' : 'user'),
			);
		}).toList());
	}

	Future<void> _toggleAdmin(_UserEntry u, bool newValue) async {
		final messenger = ScaffoldMessenger.of(context); // capture before async gap
		try {
			await FirebaseFirestore.instance.collection('users').doc(u.uid).set({
				'role': newValue ? 'admin' : 'user',
				'updatedAt': FieldValue.serverTimestamp(),
			}, SetOptions(merge: true));
			if (!mounted) return;
			messenger.showSnackBar(SnackBar(content: Text('Updated ${u.email} role: ${newValue ? 'admin' : 'user'} (claims refresh may take a minute)')));
		} catch (e) {
			if (!mounted) return;
			messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
		}
	}

	Future<void> _refreshToken() async {
		final messenger = ScaffoldMessenger.of(context);
		final user = FirebaseAuth.instance.currentUser;
		if (user == null) return;
		await user.getIdToken(true);
		if (!mounted) return;
		messenger.showSnackBar(const SnackBar(content: Text('Token refreshed')));
	}

	@override
	Widget build(BuildContext context) {
		if (!_authReady) return const Center(child: CircularProgressIndicator());
		if (_authError != null) {
			return Center(
				child: Column(mainAxisSize: MainAxisSize.min, children: [
					const Icon(Icons.error_outline, size: 40, color: Colors.redAccent),
					const SizedBox(height: 12),
					Text('Auth failed', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.redAccent)),
					Padding(
						padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
						child: Text(_authError!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
					),
					OutlinedButton.icon(onPressed: _ensureAuthed, icon: const Icon(Icons.refresh_outlined), label: const Text('Retry')),
				]),
			);
		}
		final filtered = _settings.where((s) => s.title.toLowerCase().contains(_search.toLowerCase())).toList();
		return Padding(
			padding: const EdgeInsets.all(16),
			child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
				Row(children: [
					Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search settings'), onChanged: (v) => setState(() => _search = v))),
					const SizedBox(width: 12),
					OutlinedButton.icon(onPressed: _refreshToken, icon: const Icon(Icons.refresh_outlined), label: const Text('Refresh Token')),
					const SizedBox(width: 8),
					OutlinedButton.icon(onPressed: () => setState(()=> _showUsers = !_showUsers), icon: Icon(_showUsers ? Icons.admin_panel_settings : Icons.people_alt_outlined), label: Text(_showUsers ? 'Hide Users' : 'Show Users')),
				]),
				const SizedBox(height: 16),
				if (_showUsers) _AdminUsersCard(stream: _userStream(), onToggle: _toggleAdmin),
				if (_showUsers) const SizedBox(height: 16),
				Expanded(
					child: Card(
						child: ListView.separated(
							itemCount: filtered.length,
							separatorBuilder: (_, __) => const Divider(height: 1),
							itemBuilder: (context, i) {
								final s = filtered[i];
								return ListTile(
									leading: Icon(s.icon),
									title: Text(s.title),
									subtitle: Text(s.subtitle),
									trailing: const Icon(Icons.chevron_right),
									onTap: () => _openSetting(context, s),
								);
							},
						),
					),
				),
				const SizedBox(height: 12),
				const _AboutCard(),
				const SizedBox(height: 8),
				_BuildAuthDebugInfo(),
			]),
		);
	}

	Future<void> _openSetting(BuildContext context, _SettingItem s) async {
		await showDialog(
			context: context,
			builder: (context) => AlertDialog(
				title: Text(s.title),
				content: Text('This is a placeholder for "${s.title}" configuration UI.'),
				actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
			),
		);
	}
}

class _UserEntry {
	final String uid;
	final String email;
	final bool isAdmin;
	final String role;
	_UserEntry({required this.uid, required this.email, required this.isAdmin, required this.role});
}

class _AdminUsersCard extends StatelessWidget {
	final Stream<List<_UserEntry>> stream;
	final Future<void> Function(_UserEntry, bool) onToggle;
	const _AdminUsersCard({required this.stream, required this.onToggle});

	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Row(children: const [
						Icon(Icons.admin_panel_settings_outlined), SizedBox(width: 8), Text('User Roles', style: TextStyle(fontWeight: FontWeight.bold)),
					]),
					const SizedBox(height: 8),
					StreamBuilder<List<_UserEntry>>(
						stream: stream,
						builder: (context, snap) {
							if (snap.hasError) {
								final err = snap.error.toString();
								final permission = err.contains('permission-denied');
								return Column(
									crossAxisAlignment: CrossAxisAlignment.start,
									children: [
										Text('Error loading users', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
										const SizedBox(height: 4),
										Text(permission
												? 'Permission denied. Ensure Firestore rules allow read on /users and you are signed in.'
												: err,
											style: Theme.of(context).textTheme.bodySmall),
										const SizedBox(height: 8),
										Wrap(spacing: 8, children: [
											OutlinedButton.icon(
												icon: const Icon(Icons.refresh_outlined),
												label: const Text('Retry'),
												onPressed: () => (context as Element).markNeedsBuild(),
											),
											if (permission)
												OutlinedButton.icon(
													icon: const Icon(Icons.security_outlined),
													label: const Text('Rules Help'),
													onPressed: () {
														showDialog(context: context, builder: (_) => AlertDialog(
															title: const Text('Firestore Rules Tips'),
															content: const Text('Ensure firestore.rules has a block:\nmatch /users/{userId} {\n  allow read: if request.auth!=null; } and that you deployed rules using firebase deploy --only firestore:rules'),
															actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
														));
												},
											),
										]),
									],
								);
							}
							if (!snap.hasData) return const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator());
							final users = snap.data!;
							if (users.isEmpty) return const Text('No users');
							return ListView.separated(
								shrinkWrap: true,
								physics: const NeverScrollableScrollPhysics(),
								itemCount: users.length,
								separatorBuilder: (_, __) => const Divider(height: 1),
								itemBuilder: (context, i) {
									final u = users[i];
									return SwitchListTile(
										value: u.isAdmin,
										onChanged: (v) => onToggle(u, v),
										title: Text(u.email.isEmpty ? u.uid : u.email),
										subtitle: Text(u.isAdmin ? 'Admin' : 'User'),
										secondary: Icon(u.isAdmin ? Icons.verified_user : Icons.person_outline),
									);
								},
							);
						},
					),
				]),
			),
		);
	}
}

class _AboutCard extends StatelessWidget {
	const _AboutCard();
	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Row(children: [
					const Icon(Icons.info_outline), const SizedBox(width: 8),
					const Expanded(child: Text('Admin settings are local-only in this demo. Wire to backend or Firebase Remote Config later.')),
					OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.sync_outlined), label: const Text('Sync Now')),
				]),
			),
		);
	}
}

class _SettingItem {
	final IconData icon; final String title; final String subtitle;
	_SettingItem({required this.icon, required this.title, required this.subtitle});
}

class _BuildAuthDebugInfo extends StatelessWidget {
	@override
	Widget build(BuildContext context) {
		final auth = FirebaseAuth.instance;
		final user = auth.currentUser;
		return Opacity(
			opacity: 0.6,
			child: Row(
				children: [
					const Icon(Icons.bug_report_outlined, size: 16),
					const SizedBox(width: 6),
					Expanded(
						child: Text(
							user == null
								? 'Auth: <none>'
								: 'Auth: uid=${user.uid.substring(0,6)}… anon=${user.isAnonymous} email=${user.email ?? '-'}',
							style: Theme.of(context).textTheme.bodySmall,
							overflow: TextOverflow.ellipsis,
						),
					),
					TextButton(onPressed: () async {
						try { await user?.getIdToken(true); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Token refreshed'))); } catch (_){ }
					}, child: const Text('Refresh Token')),
				],
			),
		);
	}
}
