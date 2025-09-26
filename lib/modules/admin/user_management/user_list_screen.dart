import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/store_context_provider.dart';
import '../providers/capabilities_provider.dart';

class UserDirectoryEntry {
  final String uid; final String name; final String email; final String role; final String status; final DateTime? lastLogin;
  const UserDirectoryEntry({required this.uid, required this.name, required this.email, required this.role, required this.status, this.lastLogin});
}

final userDirectoryProvider = FutureProvider.family<List<UserDirectoryEntry>, String?>((ref, storeId) async {
  if (storeId == null) return [];
  // Placeholder mock; integrate Firestore query later
  await Future.delayed(const Duration(milliseconds: 120));
  return [
    UserDirectoryEntry(uid: 'u1', name: 'Alice', email: 'alice@example.com', role: 'manager', status: 'active', lastLogin: DateTime.now().subtract(const Duration(hours:2))),
    UserDirectoryEntry(uid: 'u2', name: 'Bob', email: 'bob@example.com', role: 'cashier', status: 'active', lastLogin: DateTime.now().subtract(const Duration(days:1))),
    UserDirectoryEntry(uid: 'u3', name: 'Carol', email: 'carol@example.com', role: 'clerk', status: 'inactive'),
  ];
});

class UserListScreen extends ConsumerStatefulWidget {
  const UserListScreen({super.key});
  @override
  ConsumerState<UserListScreen> createState() => _UserListScreenState();
}

class _UserListScreenState extends ConsumerState<UserListScreen> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final storeId = ref.watch(selectedStoreIdProvider);
    final caps = ref.watch(capabilitiesProvider);
    final usersAsync = ref.watch(userDirectoryProvider(storeId));
    return Scaffold(
      appBar: AppBar(title: const Text('Users'), actions: [
        if (caps.manageUsers) IconButton(onPressed: _openInvite, icon: const Icon(Icons.person_add_alt_1_outlined)),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search users'), onChanged: (v)=> setState(()=> _search = v)),
        ),
        Expanded(child: usersAsync.when(
          data: (list){
            final filtered = list.where((u)=> u.name.toLowerCase().contains(_search.toLowerCase()) || u.email.toLowerCase().contains(_search.toLowerCase())).toList();
            if (filtered.isEmpty) return const Center(child: Text('No users'));
            return SingleChildScrollView(
              child: DataTable(columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Last Login')),
                DataColumn(label: Text('Actions')),
              ], rows: [
                for (final u in filtered) DataRow(cells: [
                  DataCell(Text(u.name)),
                  DataCell(Text(u.email)),
                  DataCell(_RoleDropdown(initial: u.role, enabled: caps.manageUsers, onChanged: (r){ /* call function */ })),
                  DataCell(Text(u.status)),
                  DataCell(Text(u.lastLogin==null? '-': _fmt(u.lastLogin!))),
                  DataCell(Row(children: [
                    if (caps.manageUsers) IconButton(onPressed: ()=> _openUserDetail(u), icon: const Icon(Icons.open_in_new, size:18)),
                  ])),
                ])
              ]),
            );
          },
          error: (e,_)=> Center(child: Text('Error: $e')),
          loading: ()=> const Center(child: CircularProgressIndicator()),
        ))
      ]),
    );
  }

  String _fmt(DateTime d){ return '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}'; }

  void _openUserDetail(UserDirectoryEntry u){
    showModalBottomSheet(context: context, builder: (_)=> SafeArea(child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children:[
        Text(u.name, style: Theme.of(context).textTheme.titleLarge),
        Text(u.email), const SizedBox(height:12),
        Text('Timeline (mock)...'),
        const SizedBox(height:12),
        FilledButton(onPressed: ()=> Navigator.pop(context), child: const Text('Close')),
      ]),
    )));
  }

  void _openInvite(){
    showDialog(context: context, builder: (_)=> const _InviteUserDialog());
  }
}

class _RoleDropdown extends StatefulWidget {
  final String initial; final bool enabled; final ValueChanged<String> onChanged;
  const _RoleDropdown({required this.initial, required this.enabled, required this.onChanged});
  @override State<_RoleDropdown> createState()=> _RoleDropdownState();
}
class _RoleDropdownState extends State<_RoleDropdown>{
  late String value;
  static const roles=['owner','manager','cashier','clerk','accountant'];
  @override void initState(){ super.initState(); value=widget.initial; }
  @override Widget build(BuildContext context){
    return DropdownButton<String>(value: value, isDense: true, onChanged: widget.enabled? (v){ if(v!=null){ setState(()=> value=v); widget.onChanged(v);} }: null, items: [
      for(final r in roles) DropdownMenuItem(value: r, child: Text(r))
    ]);
  }
}

class _InviteUserDialog extends StatefulWidget { const _InviteUserDialog(); @override State<_InviteUserDialog> createState()=> _InviteUserDialogState(); }
class _InviteUserDialogState extends State<_InviteUserDialog>{
  int step=0; String email=''; String role='cashier'; bool sending=false; String? error;
  @override Widget build(BuildContext context){
    return AlertDialog(
      title: Text('Invite User • Step ${step+1}/4'),
      content: SizedBox(width: 420, child: _buildStep()),
      actions: [
        if (step>0) TextButton(onPressed: sending? null: ()=> setState(()=> step--), child: const Text('Back')),
        TextButton(onPressed: sending? null: ()=> Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: sending? null: _next, child: Text(step==3? 'Finish':'Next')),
      ],
    );
  }
  Widget _buildStep(){
    switch(step){
      case 0: return TextField(decoration: const InputDecoration(labelText: 'Email'), onChanged: (v)=> email=v);
      case 1: return DropdownButtonFormField(value: role, decoration: const InputDecoration(labelText: 'Role'), items: const [
        DropdownMenuItem(value: 'manager', child: Text('Manager')),
        DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
        DropdownMenuItem(value: 'clerk', child: Text('Clerk')),
        DropdownMenuItem(value: 'accountant', child: Text('Accountant')),
      ], onChanged: (v){ if(v!=null) setState(()=> role=v); });
      case 2: return const Text('Select Store (auto uses current store)');
      case 3: return Text('Summary:\nEmail: $email\nRole: $role');
      default: return const SizedBox();
    }
  }
  Future<void> _next() async {
    if (step<3){ setState(()=> step++); return; }
    setState(()=> sending=true);
    await Future.delayed(const Duration(milliseconds: 600)); // mock call
    if (!mounted) return; setState(()=> sending=false); Navigator.pop(context);
  }
}
