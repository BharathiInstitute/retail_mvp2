import 'package:flutter/material.dart';

class AccountingReportsScreen extends StatelessWidget {
  const AccountingReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final reports = const ['P&L', 'GSTR', 'Reconciliation'];
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: reports.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) => ListTile(
        leading: const Icon(Icons.insert_chart_outlined),
        title: Text(reports[index]),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {},
      ),
    );
  }
}
