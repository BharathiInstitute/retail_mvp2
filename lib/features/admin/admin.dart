export 'package:retail_mvp2/modules/admin/admin.dart';
import 'package:flutter/material.dart';

// Consolidated Admin module in a single file.
// Combines the main AdminModuleScreen and a simple AdminScreen list view.

class AdminModuleScreen extends StatefulWidget {
  const AdminModuleScreen({super.key});
  @override
  State<AdminModuleScreen> createState() => _AdminModuleScreenState();
}

class _AdminModuleScreenState extends State<AdminModuleScreen> {
  final List<_User> _users = [
    _User(name: 'Alice Owner', email: 'alice@acme.com', role: 'Owner', active: true),
    _User(name: 'Bob Manager', email: 'bob@acme.com', role: 'Manager', active: true),
    _User(name: 'Carol Cashier', email: 'carol@acme.com', role: 'Cashier', active: false),
    _User(name: 'Dave Clerk', email: 'dave@acme.com', role: 'Clerk', active: true),
    _User(name: 'Eve Accountant', email: 'eve@acme.com', role: 'Accountant', active: true),
  ];

  final List<_Tenant> _tenants = const [
    _Tenant(id: 't1', name: 'Acme Retail', createdAt: '2024-01-15'),
    _Tenant(id: 't2', name: 'Bravo Stores', createdAt: '2024-05-10'),
  ];
  late _Tenant _selectedTenant;

  final List<_Audit> _audits = [
    _Audit(date: DateTime.now().subtract(const Duration(hours: 3)), action: 'User Created', by: 'Alice'),
    _Audit(date: DateTime.now().subtract(const Duration(hours: 2)), action: 'Role Changed (Carol → Cashier)', by: 'Bob'),
    _Audit(date: DateTime.now().subtract(const Duration(hours: 1)), action: 'Password Reset (Dave)', by: 'Alice'),
  ];

  final List<_Store> _stores = [
    _Store(name: 'Main Branch', location: 'Chennai', active: true),
    _Store(name: 'City Center', location: 'Bengaluru', active: false),
  ];

  double gstRate = 18.0;
  double defaultTax = 5.0;
  String invoiceTemplate = 'Standard';

  bool otpSent = false;
  bool otpVerified = false;

  @override
  void initState() {
    super.initState();
    _selectedTenant = _tenants.first;
  }

  void _addUser() => showDialog(
        context: context,
        builder: (context) => const AlertDialog(title: Text('Add User (Demo)'), content: Text('Placeholder form. Integrate backend later.'), actions: [
          CloseButton(),
        ]),
      );
  void _editUser(_User user) => showDialog(
        context: context,
        builder: (context) => AlertDialog(title: const Text('Edit User (Demo)'), content: Text('Edit ${user.name} — placeholder only.'), actions: const [CloseButton()]),
      );
  void _deleteUser(_User user) {
    setState(() => _users.remove(user));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted ${user.name} (demo)')));
  }
  void _resetPassword(_User user) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Password reset link sent to ${user.email} (demo)')));
  void _sendOtp() {
    setState(() => otpSent = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP sent (demo)')));
  }
  void _verifyOtp() {
    if (!otpSent) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Send OTP first')));
      return;
    }
    setState(() => otpVerified = true);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP verified (demo)')));
  }
  void _addStore() => setState(() => _stores.add(_Store(name: 'New Store', location: 'Pune', active: true)));

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 1100;
    final roleMatrix = _RoleMatrix(users: _users);
    final userCrud = _UserCrud(users: _users, onAdd: _addUser, onEdit: _editUser, onDelete: _deleteUser, onResetPassword: _resetPassword);
    final tenantCard = _TenantCard(tenant: _selectedTenant, tenants: _tenants, onSwitch: (t) => setState(() => _selectedTenant = t));
    final auditLog = _AuditLog(audits: _audits);
    final storeConfig = _StoreConfig(stores: _stores, onAdd: _addStore);
    final settingsCard = _SettingsCard(
      gstRate: gstRate,
      defaultTax: defaultTax,
      invoiceTemplate: invoiceTemplate,
      onChanged: (g, d, t) => setState(() {
        gstRate = g;
        defaultTax = d;
        invoiceTemplate = t;
      }),
    );
    final signupCard = _SignupOtpCard(otpSent: otpSent, otpVerified: otpVerified, onSend: _sendOtp, onVerify: _verifyOtp);

    if (isWide) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: ListView(children: [tenantCard, const SizedBox(height: 12), roleMatrix, const SizedBox(height: 12), userCrud, const SizedBox(height: 12), storeConfig]),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ListView(children: [settingsCard, const SizedBox(height: 12), signupCard, const SizedBox(height: 12), auditLog]),
          ),
        ]),
      );
    }

    return ListView(padding: const EdgeInsets.all(16), children: [
      tenantCard,
      const SizedBox(height: 12),
      roleMatrix,
      const SizedBox(height: 12),
      userCrud,
      const SizedBox(height: 12),
      settingsCard,
      const SizedBox(height: 12),
      signupCard,
      const SizedBox(height: 12),
      storeConfig,
      const SizedBox(height: 12),
      auditLog,
    ]);
  }
}

// Simple alternative Admin landing
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(children: const [
        ListTile(leading: Icon(Icons.group_outlined), title: Text('Users'), subtitle: Text('TODO: Manage users and roles')),
        Divider(),
        ListTile(leading: Icon(Icons.business_outlined), title: Text('Tenants'), subtitle: Text('TODO: Tenant setup and settings')),
        Divider(),
        ListTile(leading: Icon(Icons.settings_outlined), title: Text('Settings'), subtitle: Text('TODO: App settings')),
      ]),
    );
  }
}

// ===== Widgets =====
class _RoleMatrix extends StatelessWidget {
  final List<_User> users;
  const _RoleMatrix({required this.users});
  @override
  Widget build(BuildContext context) {
    const roles = ['Owner', 'Manager', 'Cashier', 'Clerk', 'Accountant'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Role-based Access', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(columns: [
              const DataColumn(label: Text('User')),
              for (final r in roles) DataColumn(label: Text(r)),
            ], rows: [
              for (final u in users)
                DataRow(cells: [
                  DataCell(Text(u.name)),
                  ...roles.map((r) {
                    final on = u.role == r;
                    return DataCell(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: on ? Theme.of(context).colorScheme.primary.withValues(alpha: .15) : null,
                        borderRadius: BorderRadius.circular(6),
                        border: on ? Border.all(color: Theme.of(context).colorScheme.primary) : null,
                      ),
                      child: Center(child: Icon(on ? Icons.check : Icons.close, size: 16)),
                    ));
                  }),
                ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _UserCrud extends StatelessWidget {
  final List<_User> users;
  final void Function(_User) onEdit;
  final void Function(_User) onDelete;
  final void Function(_User) onResetPassword;
  final VoidCallback onAdd;
  const _UserCrud({required this.users, required this.onEdit, required this.onDelete, required this.onResetPassword, required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Users', style: Theme.of(context).textTheme.titleMedium),
            FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('Add User')),
          ]),
          const SizedBox(height: 8),
          ListView.separated(
            itemCount: users.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final u = users[i];
              return ListTile(
                leading: CircleAvatar(child: Text(u.name.substring(0, 1))),
                title: Text(u.name),
                subtitle: Text('${u.email} • ${u.role}${u.active ? '' : ' • Inactive'}'),
                trailing: Wrap(spacing: 8, children: [
                  IconButton(onPressed: () => onEdit(u), icon: const Icon(Icons.edit_outlined)),
                  IconButton(onPressed: () => onDelete(u), icon: const Icon(Icons.delete_outline)),
                  IconButton(onPressed: () => onResetPassword(u), icon: const Icon(Icons.lock_reset_outlined)),
                  IconButton(onPressed: () {}, icon: const Icon(Icons.visibility_outlined)),
                ]),
              );
            },
          ),
        ]),
      ),
    );
  }
}

class _TenantCard extends StatelessWidget {
  final _Tenant tenant;
  final List<_Tenant> tenants;
  final ValueChanged<_Tenant> onSwitch;
  const _TenantCard({required this.tenant, required this.tenants, required this.onSwitch});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Tenant / Company', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: ListTile(title: Text(tenant.name), subtitle: Text('ID: ${tenant.id} • Created: ${tenant.createdAt}'))),
            DropdownButton<_Tenant>(
              value: tenant,
              onChanged: (t) => t != null ? onSwitch(t) : null,
              items: [for (final t in tenants) DropdownMenuItem(value: t, child: Text(t.name))],
            ),
          ]),
        ]),
      ),
    );
  }
}

class _AuditLog extends StatelessWidget {
  final List<_Audit> audits;
  const _AuditLog({required this.audits});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Audit Log', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListView.separated(
            itemCount: audits.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final a = audits[i];
              return ListTile(
                leading: const Icon(Icons.history_outlined),
                title: Text(a.action),
                subtitle: Text('${a.date.toLocal()} • by ${a.by}'),
              );
            },
          ),
        ]),
      ),
    );
  }
}

class _StoreConfig extends StatelessWidget {
  final List<_Store> stores;
  final VoidCallback onAdd;
  const _StoreConfig({required this.stores, required this.onAdd});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Stores / Branches', style: Theme.of(context).textTheme.titleMedium),
            OutlinedButton.icon(onPressed: onAdd, icon: const Icon(Icons.add_business_outlined), label: const Text('Add Store')),
          ]),
          const SizedBox(height: 8),
          ListView.separated(
            itemCount: stores.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final s = stores[i];
              return ListTile(
                leading: Icon(Icons.store_mall_directory_outlined, color: s.active ? Colors.green : Colors.red),
                title: Text(s.name),
                subtitle: Text('${s.location} • ${s.active ? 'Active' : 'Inactive'}'),
              );
            },
          ),
        ]),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final double gstRate;
  final double defaultTax;
  final String invoiceTemplate;
  final void Function(double, double, String) onChanged;
  const _SettingsCard({required this.gstRate, required this.defaultTax, required this.invoiceTemplate, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    final gstController = TextEditingController(text: gstRate.toStringAsFixed(0));
    final defaultTaxController = TextEditingController(text: defaultTax.toStringAsFixed(0));
    final templates = const ['Standard', 'Compact', 'Detailed'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Central Tax & Invoice Template Settings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(runSpacing: 12, spacing: 12, children: [
            SizedBox(
              width: 220,
              child: TextField(
                controller: gstController,
                decoration: const InputDecoration(labelText: 'GST Rate (%)', prefixIcon: Icon(Icons.percent)),
                keyboardType: TextInputType.number,
                onChanged: (v) => onChanged(double.tryParse(v) ?? gstRate, defaultTax, invoiceTemplate),
              ),
            ),
            SizedBox(
              width: 220,
              child: TextField(
                controller: defaultTaxController,
                decoration: const InputDecoration(labelText: 'Default Tax (%)', prefixIcon: Icon(Icons.percent)),
                keyboardType: TextInputType.number,
                onChanged: (v) => onChanged(gstRate, double.tryParse(v) ?? defaultTax, invoiceTemplate),
              ),
            ),
            DropdownButton<String>(
              value: invoiceTemplate,
              onChanged: (v) => onChanged(gstRate, defaultTax, v ?? invoiceTemplate),
              items: [for (final t in templates) DropdownMenuItem(value: t, child: Text('Template: $t'))],
            ),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .5),
            ),
            child: Row(children: [const Icon(Icons.receipt_long_outlined), const SizedBox(width: 8), Text('Invoice Preview • $invoiceTemplate')]),
          ),
        ]),
      ),
    );
  }
}

class _SignupOtpCard extends StatelessWidget {
  final bool otpSent;
  final bool otpVerified;
  final VoidCallback onSend;
  final VoidCallback onVerify;
  const _SignupOtpCard({required this.otpSent, required this.otpVerified, required this.onSend, required this.onVerify});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Signup Verification (Email/OTP)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            Chip(label: Text(otpSent ? 'OTP Sent' : 'OTP Not Sent'), avatar: Icon(otpSent ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined, size: 16)),
            const SizedBox(width: 8),
            Chip(label: Text(otpVerified ? 'Verified' : 'Not Verified'), avatar: Icon(otpVerified ? Icons.verified_outlined : Icons.verified_user_outlined, size: 16)),
            const Spacer(),
            OutlinedButton(onPressed: onSend, child: const Text('Send OTP')),
            const SizedBox(width: 8),
            FilledButton(onPressed: onVerify, child: const Text('Verify OTP')),
          ]),
          const SizedBox(height: 8),
          Text('Demo only — integrate with Auth/Email service later.', style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}

// ===== Demo data classes =====
class _User { final String name; final String email; final String role; final bool active; _User({required this.name, required this.email, required this.role, required this.active}); }
class _Tenant { final String id; final String name; final String createdAt; const _Tenant({required this.id, required this.name, required this.createdAt}); @override String toString() => name; }
class _Audit { final DateTime date; final String action; final String by; _Audit({required this.date, required this.action, required this.by}); }
class _Store { final String name; final String location; final bool active; _Store({required this.name, required this.location, required this.active}); }

// TODO: Future models/services can be added here or refactored into separate files if needed.
