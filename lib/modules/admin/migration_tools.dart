import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:retail_mvp2/modules/stores/providers.dart';

class MigrationToolsScreen extends ConsumerStatefulWidget {
  const MigrationToolsScreen({super.key});
  @override
  ConsumerState<MigrationToolsScreen> createState() => _MigrationToolsScreenState();
}

class _MigrationToolsScreenState extends ConsumerState<MigrationToolsScreen> {
  bool dryRun = true;
  bool whereMissingOnly = true;
  int batchSize = 300;
  List<String> collections = const [
    'inventory',
    'customers',
    'invoices',
    'purchase_invoices',
    'stock_movements',
    'suppliers',
    'alerts',
    'loyalty',
    'loyalty_settings',
  ];
  bool running = false;
  dynamic result;
  String? error;

  Future<void> _run({String? storeId}) async {
    setState(() { running = true; error = null; });
    try {
      final fun = FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable('backfillTopToSub');
      final resp = await fun.call({
        'collections': collections,
        'batchSize': batchSize,
        'dryRun': dryRun,
        'storeId': storeId,
        'whereMissingOnly': whereMissingOnly,
      });
      setState(() { result = resp.data; });
    } catch (e) {
      setState(() { error = e.toString(); });
    } finally {
      setState(() { running = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = ref.watch(selectedStoreIdProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Migration Tools')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 12, runSpacing: 8, children: [
              FilterChip(
                label: const Text('Dry run'),
                selected: dryRun,
                onSelected: (v) => setState(() => dryRun = v),
              ),
              FilterChip(
                label: const Text('Only missing'),
                selected: whereMissingOnly,
                onSelected: (v) => setState(() => whereMissingOnly = v),
              ),
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Batch:'),
                const SizedBox(width: 6),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    initialValue: batchSize.toString(),
                    onChanged: (v) { final n = int.tryParse(v.trim()); if (n != null && n > 0) setState(() => batchSize = n); },
                    keyboardType: const TextInputType.numberWithOptions(decimal: false),
                    decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                  ),
                ),
              ]),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ElevatedButton.icon(
                onPressed: running ? null : () => _run(),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Run (All Stores)')
              ),
              ElevatedButton.icon(
                onPressed: running || sel == null ? null : () => _run(storeId: sel),
                icon: const Icon(Icons.store_mall_directory_outlined),
                label: Text('Run for Store (${sel ?? '-'})')
              ),
              ElevatedButton.icon(
                onPressed: running ? null : () { setState(() { dryRun = true; }); _run(storeId: sel); },
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('Dry run (Selected)')
              ),
            ]),
            const SizedBox(height: 16),
            if (running) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Running...'),
            ],
            if (error != null) ...[
              Text('Error: $error', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: _ResultView(data: result),
            ),
            const Divider(),
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                'Note: Owner only. Uses callable backfillTopToSub (us-central1). Ensure indexes and rules are deployed. ',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  final dynamic data;
  const _ResultView({required this.data});
  @override
  Widget build(BuildContext context) {
    if (data == null) {
      return const Center(child: Text('No results yet'));
    }
    try {
      final m = data as Map;
      final ok = m['ok'] == true;
      final summary = (m['summary'] as List?)?.whereType<Map>().toList() ?? const [];
      if (!ok) return Text('Unexpected response: $data');
      if (summary.isEmpty) return const Text('Summary empty');
      return ListView.separated(
        itemCount: summary.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final s = summary[i];
          final col = s['collection'];
          final target = s['target'];
          final processed = s['processed'];
          final copied = s['copied'];
          final skipped = s['skipped'];
          final errors = s['errors'];
          return ListTile(
            title: Text('$col → $target'),
            subtitle: Text('processed: $processed   copied: $copied   skipped: $skipped   errors: $errors'),
          );
        },
      );
    } catch (_) {
      return SingleChildScrollView(
        child: Text('Raw: $data'),
      );
    }
  }
}
