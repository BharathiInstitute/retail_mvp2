import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_claims_provider.dart';
import 'store_context_provider.dart';

class Capabilities {
  final bool manageUsers;
  final bool editSettings;
  final bool viewAudit;
  final bool createInvoice;
  final bool editProducts;
  final bool adjustStock;
  final bool viewFinance;
  const Capabilities({
    required this.manageUsers,
    required this.editSettings,
    required this.viewAudit,
    required this.createInvoice,
    required this.editProducts,
    required this.adjustStock,
    required this.viewFinance,
  });
}

final capabilitiesProvider = Provider.autoDispose<Capabilities>((ref) {
  final auth = ref.watch(authUserProvider).asData?.value;
  final membership = ref.watch(activeMembershipProvider).value;
  final active = auth?.active ?? false;
  final storeRole = membership?['role'] ?? auth?.storeRoles[ref.watch(selectedStoreIdProvider)] ;
  final globalRole = auth?.claims['role'];
  final isOwner = globalRole == 'owner' || storeRole == 'owner';
  bool can(List<String> roles) => active && (isOwner || (storeRole != null && roles.contains(storeRole)));
  return Capabilities(
    manageUsers: can(const ['owner','manager']),
    editSettings: can(const ['owner','manager']),
    viewAudit: can(const ['owner','manager','accountant']),
    createInvoice: can(const ['owner','manager','cashier']),
    editProducts: can(const ['owner','manager','clerk']),
    adjustStock: can(const ['owner','manager','clerk']),
    viewFinance: can(const ['owner','manager','accountant']),
  );
});
