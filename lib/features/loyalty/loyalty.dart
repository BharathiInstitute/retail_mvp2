import 'package:flutter/material.dart';

// Loyalty consolidated into a single file.
// Exposes LoyaltyModuleScreen; contains demo UI, models, and helpers.

class LoyaltyModuleScreen extends StatefulWidget {
  const LoyaltyModuleScreen({super.key});
  @override
  State<LoyaltyModuleScreen> createState() => _LoyaltyModuleScreenState();
}

class _LoyaltyModuleScreenState extends State<LoyaltyModuleScreen> {
  final List<_CustomerProfile> _customers = const [
    _CustomerProfile(id: 'c1', name: 'Alice'),
    _CustomerProfile(id: 'c2', name: 'Bob'),
  ];

  final List<_LoyaltyTx> _transactions = [
    _LoyaltyTx(date: DateTime.now().subtract(const Duration(days: 1)), type: _TxType.earn, points: 20, customerId: 'c1', customerName: 'Alice'),
    _LoyaltyTx(date: DateTime.now().subtract(const Duration(days: 2)), type: _TxType.redeem, points: -10, customerId: 'c1', customerName: 'Alice'),
    _LoyaltyTx(date: DateTime.now().subtract(const Duration(days: 3)), type: _TxType.earn, points: 15, customerId: 'c2', customerName: 'Bob'),
    _LoyaltyTx(date: DateTime.now().subtract(const Duration(days: 4)), type: _TxType.earn, points: 5, customerId: 'c1', customerName: 'Alice'),
    _LoyaltyTx(date: DateTime.now().subtract(const Duration(days: 5)), type: _TxType.redeem, points: -5, customerId: 'c2', customerName: 'Bob'),
  ];

  _LoyaltyRules rules = const _LoyaltyRules(spendPerPoint: 100, valuePerPoint: 1);

  late _CustomerProfile _selectedCustomer;
  final TextEditingController _amountController = TextEditingController(text: '500');
  final TextEditingController _redeemController = TextEditingController(text: '10');

  @override
  void initState() {
    super.initState();
    _selectedCustomer = _customers.first;
  }

  @override
  void dispose() {
    _amountController.dispose();
    _redeemController.dispose();
    super.dispose();
  }

  int _pointsForAmount(int rupees) => (rupees / rules.spendPerPoint).floor();

  void _earnPointsFromAmount() {
    final amt = int.tryParse(_amountController.text.trim()) ?? 0;
    final pts = _pointsForAmount(amt);
    if (pts <= 0) {
      _showSnack('Enter a valid amount to earn points');
      return;
    }
    setState(() {
      _transactions.insert(
        0,
        _LoyaltyTx(
          date: DateTime.now(),
          type: _TxType.earn,
          points: pts,
          customerId: _selectedCustomer.id,
          customerName: _selectedCustomer.name,
        ),
      );
    });
    _showSnack('Earned $pts pts for ₹$amt (demo)');
  }

  void _redeemPoints() {
    final pts = int.tryParse(_redeemController.text.trim()) ?? 0;
    if (pts <= 0) {
      _showSnack('Enter points to redeem');
      return;
    }
    final available = _availablePointsFor(_selectedCustomer.id);
    if (pts > available) {
      _showSnack('Not enough points (available: $available)');
      return;
    }
    setState(() {
      _transactions.insert(
        0,
        _LoyaltyTx(
          date: DateTime.now(),
          type: _TxType.redeem,
          points: -pts,
          customerId: _selectedCustomer.id,
          customerName: _selectedCustomer.name,
        ),
      );
    });
    _showSnack('Redeemed $pts pts (₹${pts * rules.valuePerPoint}) (demo)');
  }

  void _showSnack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  int _earnedFor(String customerId) => _transactions
      .where((t) => t.customerId == customerId && t.type == _TxType.earn)
      .fold<int>(0, (sum, t) => sum + t.points);

  int _redeemedFor(String customerId) => _transactions
      .where((t) => t.customerId == customerId && t.type == _TxType.redeem)
      .fold<int>(0, (sum, t) => sum + (-t.points));

  int _availablePointsFor(String customerId) => _earnedFor(customerId) - _redeemedFor(customerId);

  int get _totalIssued => _transactions.where((t) => t.type == _TxType.earn).fold<int>(0, (sum, t) => sum + t.points);
  int get _totalRedeemed => _transactions.where((t) => t.type == _TxType.redeem).fold<int>(0, (sum, t) => sum + (-t.points));

  String _badgeFor(int points) {
    if (points >= 200) return 'Gold';
    if (points >= 100) return 'Silver';
    return 'Bronze';
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;
    final available = _availablePointsFor(_selectedCustomer.id);
    final earned = _earnedFor(_selectedCustomer.id);
    final redeemed = _redeemedFor(_selectedCustomer.id);

    final profileCard = _ProfileCard(
      customer: _selectedCustomer,
      available: available,
      earned: earned,
      redeemed: redeemed,
      badge: _badgeFor(available),
      onCustomerChanged: (c) => setState(() => _selectedCustomer = c),
      customers: _customers,
    );

    final actionsCard = _ActionsCard(
      amountController: _amountController,
      redeemController: _redeemController,
      rules: rules,
      onEarn: _earnPointsFromAmount,
      onRedeem: _redeemPoints,
    );

    final rulesCard = _RulesCard(
      rules: rules,
      onEdit: () {},
    );

    final transactionsCard = _TransactionsCard(transactions: _transactions);
    final chartCard = _IssuedRedeemedChart(issued: _totalIssued, redeemed: _totalRedeemed);

    if (isWide) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: ListView(
                children: [
                  profileCard,
                  const SizedBox(height: 12),
                  actionsCard,
                  const SizedBox(height: 12),
                  rulesCard,
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 3,
              child: ListView(
                children: [
                  chartCard,
                  const SizedBox(height: 12),
                  transactionsCard,
                ],
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        profileCard,
        const SizedBox(height: 12),
        actionsCard,
        const SizedBox(height: 12),
        rulesCard,
        const SizedBox(height: 12),
        chartCard,
        const SizedBox(height: 12),
        transactionsCard,
      ],
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final _CustomerProfile customer;
  final List<_CustomerProfile> customers;
  final int available;
  final int earned;
  final int redeemed;
  final String badge;
  final ValueChanged<_CustomerProfile> onCustomerChanged;
  const _ProfileCard({required this.customer, required this.customers, required this.available, required this.earned, required this.redeemed, required this.badge, required this.onCustomerChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(
            children: [
              const CircleAvatar(radius: 24, child: Icon(Icons.person)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(customer.name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(width: 8),
                    Chip(avatar: const Icon(Icons.star, size: 16), label: Text(badge)),
                  ]),
                  const SizedBox(height: 4),
                  Text('Customer ID: ${customer.id}', style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              DropdownButton<_CustomerProfile>(
                value: customer,
                onChanged: (c) => c != null ? onCustomerChanged(c) : null,
                items: [for (final c in customers) DropdownMenuItem(value: c, child: Text(c.name))],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 12, children: const [
            _MetricTile(title: 'Available', value: '—', icon: Icons.savings_outlined),
            _MetricTile(title: 'Earned', value: '—', icon: Icons.trending_up),
            _MetricTile(title: 'Redeemed', value: '—', icon: Icons.trending_down),
          ]),
        ]),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  const _MetricTile({required this.title, required this.value, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ]),
      ]),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  final TextEditingController amountController;
  final TextEditingController redeemController;
  final _LoyaltyRules rules;
  final VoidCallback onEarn;
  final VoidCallback onRedeem;
  const _ActionsCard({required this.amountController, required this.redeemController, required this.rules, required this.onEarn, required this.onRedeem});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Earn / Redeem at POS', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: amountController,
                decoration: InputDecoration(labelText: 'Amount spent (₹)', helperText: '₹${rules.spendPerPoint} = 1 pt', prefixIcon: const Icon(Icons.currency_rupee)),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(onPressed: onEarn, icon: const Icon(Icons.add), label: const Text('Earn')),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: redeemController,
                decoration: InputDecoration(labelText: 'Points to redeem', helperText: '1 pt = ₹${rules.valuePerPoint}', prefixIcon: const Icon(Icons.star_border)),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(onPressed: onRedeem, icon: const Icon(Icons.remove), label: const Text('Redeem')),
          ]),
          const SizedBox(height: 8),
          Text('Demo only — no backend calls. ', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _RulesCard extends StatelessWidget {
  final _LoyaltyRules rules;
  final VoidCallback onEdit;
  const _RulesCard({required this.rules, required this.onEdit});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Earning & Redemption Rules', style: Theme.of(context).textTheme.titleMedium),
            TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined), label: const Text('Edit')),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 12, children: const [
            _InfoChip(icon: Icons.currency_rupee, label: '₹100 spent = 1 pt'),
            _InfoChip(icon: Icons.swap_horiz, label: '1 pt = ₹1 value'),
          ]),
          const SizedBox(height: 8),
          Text('TODO: Persist and fetch rules from backend (Firestore/Functions).', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _TransactionsCard extends StatelessWidget {
  final List<_LoyaltyTx> transactions;
  const _TransactionsCard({required this.transactions});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), child: Text('Recent Loyalty Transactions', style: Theme.of(context).textTheme.titleMedium)),
          const Divider(height: 1),
          ListView.separated(
            itemCount: transactions.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final t = transactions[i];
              final isEarn = t.type == _TxType.earn;
              final pts = isEarn ? '+${t.points}' : '${t.points}';
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: isEarn ? Colors.green.withValues(alpha: .15) : Colors.red.withValues(alpha: .15),
                  child: Icon(isEarn ? Icons.trending_up : Icons.trending_down, color: isEarn ? Colors.green : Colors.red),
                ),
                title: Text('${t.customerName} • $pts pts'),
                subtitle: Text('${t.date.toLocal()}'),
              );
            },
          ),
        ]),
      ),
    );
  }
}

class _IssuedRedeemedChart extends StatelessWidget {
  final int issued;
  final int redeemed;
  const _IssuedRedeemedChart({required this.issued, required this.redeemed});
  @override
  Widget build(BuildContext context) {
    final total = (issued + redeemed).clamp(1, 1 << 31);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Points Issued vs Redeemed', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final maxW = constraints.maxWidth;
            final issuedW = maxW * (issued / total);
            final redeemedW = maxW * (redeemed / total);
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _Bar(label: 'Issued', color: Colors.indigo, width: issuedW, value: issued),
              const SizedBox(height: 8),
              _Bar(label: 'Redeemed', color: Colors.orange, width: redeemedW, value: redeemed),
            ]);
          }),
          const SizedBox(height: 8),
          Wrap(spacing: 12, children: const [
            _LegendDot(color: Colors.indigo, label: 'Issued'),
            _LegendDot(color: Colors.orange, label: 'Redeemed'),
          ]),
          const SizedBox(height: 8),
          Text('Demo chart — replace with charts library if needed.\nTODO: Source data from backend.', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Chip(avatar: Icon(icon, size: 16), label: Text(label));
}

class _Bar extends StatelessWidget {
  final String label;
  final Color color;
  final double width;
  final int value;
  const _Bar({required this.label, required this.color, required this.width, required this.value});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$label ($value)'),
      const SizedBox(height: 4),
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 20, maxHeight: 14),
        child: Container(height: 14, width: width, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6))),
      ),
    ]);
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label),
    ]);
  }
}

class _CustomerProfile {
  final String id;
  final String name;
  const _CustomerProfile({required this.id, required this.name});
  @override
  String toString() => name;
}

enum _TxType { earn, redeem }

class _LoyaltyTx {
  final DateTime date;
  final _TxType type;
  final int points;
  final String customerId;
  final String customerName;
  _LoyaltyTx({required this.date, required this.type, required this.points, required this.customerId, required this.customerName});
}

class _LoyaltyRules {
  final int spendPerPoint;
  final int valuePerPoint;
  const _LoyaltyRules({required this.spendPerPoint, required this.valuePerPoint});
}
