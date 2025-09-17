import 'package:flutter/material.dart';

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

	@override
	Widget build(BuildContext context) {
		final filtered = _settings.where((s) => s.title.toLowerCase().contains(_search.toLowerCase())).toList();
		return Padding(
			padding: const EdgeInsets.all(16),
			child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
				Row(children: [
					Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search settings'), onChanged: (v) => setState(() => _search = v))),
					const SizedBox(width: 12),
					OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.save_outlined), label: const Text('Export Config')),
				]),
				const SizedBox(height: 16),
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
