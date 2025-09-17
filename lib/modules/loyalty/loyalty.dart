import 'package:flutter/material.dart';

class LoyaltyModuleScreen extends StatefulWidget {
	const LoyaltyModuleScreen({super.key});
	@override
	State<LoyaltyModuleScreen> createState() => _LoyaltyModuleScreenState();
}

class _LoyaltyModuleScreenState extends State<LoyaltyModuleScreen> {
	final List<_Member> _members = [
		_Member(name: 'Alice', points: 1240, tier: 'Gold', lastPurchase: DateTime.now().subtract(const Duration(days: 2))),
		_Member(name: 'Bob', points: 320, tier: 'Bronze', lastPurchase: DateTime.now().subtract(const Duration(days: 10))),
		_Member(name: 'Carol', points: 780, tier: 'Silver', lastPurchase: DateTime.now().subtract(const Duration(days: 5))),
	];

	String _search = '';
	String _tierFilter = 'All';

	void _awardPoints(_Member m, int pts) {
		setState(() => m.points += pts);
		ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Awarded $pts pts to ${m.name}')));
	}

	void _redeemPoints(_Member m, int pts) {
		if (m.points < pts) return;
		setState(() => m.points -= pts);
		ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Redeemed $pts pts from ${m.name}')));
	}

	@override
	Widget build(BuildContext context) {
		final filtered = _members.where((m) {
			final matchesSearch = _search.isEmpty || m.name.toLowerCase().contains(_search.toLowerCase());
			final matchesTier = _tierFilter == 'All' || m.tier == _tierFilter;
			return matchesSearch && matchesTier;
		}).toList();

		return Padding(
			padding: const EdgeInsets.all(16),
			child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
				Wrap(spacing: 12, runSpacing: 12, children: [
					SizedBox(
						width: 260,
						child: TextField(
							decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search members'),
							onChanged: (v) => setState(() => _search = v),
						),
					),
					DropdownButton<String>(
						value: _tierFilter,
						items: const [DropdownMenuItem(value: 'All', child: Text('All Tiers')), DropdownMenuItem(value: 'Bronze', child: Text('Bronze')), DropdownMenuItem(value: 'Silver', child: Text('Silver')), DropdownMenuItem(value: 'Gold', child: Text('Gold'))],
						onChanged: (v) => setState(() => _tierFilter = v ?? 'All'),
					),
					const Spacer(),
					FilledButton.icon(onPressed: () => _bulkAward(context), icon: const Icon(Icons.card_giftcard_outlined), label: const Text('Bulk Award')),
					OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.file_download_outlined), label: const Text('Export CSV')),
				]),
				const SizedBox(height: 16),
				Expanded(
					child: Card(
						child: ListView.separated(
							itemCount: filtered.length,
							separatorBuilder: (_, __) => const Divider(height: 1),
							itemBuilder: (context, i) {
								final m = filtered[i];
								return ListTile(
									leading: CircleAvatar(child: Text(m.name.substring(0, 1)) ),
									title: Text(m.name),
									subtitle: Text('${m.tier} • Last: ${m.lastPurchase.toLocal().toString().split(' ').first}'),
									trailing: Wrap(spacing: 8, children: [
										Chip(label: Text('${m.points} pts')),
										IconButton(tooltip: 'Award 50', onPressed: () => _awardPoints(m, 50), icon: const Icon(Icons.add_circle_outline)),
										IconButton(tooltip: 'Redeem 50', onPressed: () => _redeemPoints(m, 50), icon: const Icon(Icons.remove_circle_outline)),
									]),
								);
							},
						),
					),
				),
				const SizedBox(height: 12),
				const _EarningRulesCard(),
			]),
		);
	}

	Future<void> _bulkAward(BuildContext context) async {
		final controller = TextEditingController(text: '100');
		final value = await showDialog<int>(
			context: context,
			builder: (context) => AlertDialog(
				title: const Text('Bulk Award Points'),
				content: TextField(controller: controller, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Points to award')),
				actions: [
					TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
					FilledButton(onPressed: () => Navigator.pop(context, int.tryParse(controller.text) ?? 0), child: const Text('Apply')),
				],
			),
		);
			if (value == null || value <= 0) return;
			if (!context.mounted) return; // ensure context is safe after await
			setState(() { for (final m in _members) { m.points += value; } });
			ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Awarded $value points to all filtered members')));
	}
}

class _EarningRulesCard extends StatelessWidget {
	const _EarningRulesCard();
	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Text('Earning & Redemption Rules', style: Theme.of(context).textTheme.titleMedium),
					const SizedBox(height: 8),
					const Text('• 1 point per ₹100 spent\n• Gold: 1.5x earning\n• Redemption: min 200 points'),
					const SizedBox(height: 8),
					OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.edit_outlined), label: const Text('Edit Rules')),
				]),
			),
		);
	}
}

class _Member {
	_Member({required this.name, required this.points, required this.tier, required this.lastPurchase});
	final String name; int points; final String tier; final DateTime lastPurchase;
}
