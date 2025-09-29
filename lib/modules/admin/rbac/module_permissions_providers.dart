import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_rbac_providers.dart';

// Firestore collection containing module/page permission documents.
// Each document shape (id usually == moduleKey):
// {
//   moduleKey: 'inventory',
//   label: 'Inventory',
//   allowedRoles: ['owner','manager','cashier']
// }
// Semantics:
//  - If a permission document exists for moduleKey, access is granted only if
//    the current user's role is in allowedRoles.
//  - If NO document exists for a moduleKey, we fallback to an "open" policy
//    (return true) to avoid breaking existing screens. Adjust this easily by
//    changing the fallback logic below.
//  - An empty allowedRoles list means nobody has access (closed).
//  - Owners are always granted access (override) unless an existing doc
//    explicitly has an empty list (treat that as a hard deny for consistency).

final _permissionsCollection = FirebaseFirestore.instance.collection('permissions');

class ModulePermission {
  final String moduleKey;
  final List<String> readRoles;
  final List<String> createRoles;
  final List<String> updateRoles;
  final List<String> deleteRoles;
  const ModulePermission({required this.moduleKey, required this.readRoles, required this.createRoles, required this.updateRoles, required this.deleteRoles});
}

/// Raw stream of permission documents -> Map(moduleKey -> ModulePermission)
final modulePermissionsProvider = StreamProvider<Map<String,ModulePermission>>((ref){
  return _permissionsCollection.snapshots().map((snap){
    final map = <String,ModulePermission>{};
    for(final d in snap.docs){
      final data = d.data();
      final moduleKey = (data['moduleKey'] as String?) ?? d.id;
      // Backward compat: allowedRoles used for read+all actions when new fields absent.
      final legacy = (data['allowedRoles'] as List?)?.whereType<String>().toList();
      List<String> _norm(List? l) => l?.whereType<String>().toList() ?? (legacy ?? const <String>[]);
      final read = _norm(data['readRoles'] as List?);
      final create = _norm(data['createRoles'] as List?);
      final update = _norm(data['updateRoles'] as List?);
      final del = _norm(data['deleteRoles'] as List?);
      map[moduleKey] = ModulePermission(moduleKey: moduleKey, readRoles: read, createRoles: create, updateRoles: update, deleteRoles: del);
    }
    return map;
  });
});

/// Family provider to evaluate access for a module key.
final moduleAccessProvider = Provider.family<bool, String>((ref, moduleKey){
  final user = ref.watch(appUserProvider);
  if(user == null) return false; // not signed in
  final role = user.role;
  if(role == null) return false;

  final permsMapAsync = ref.watch(modulePermissionsProvider);
  return permsMapAsync.when(
    data: (perms){
      final p = perms[moduleKey];
      if(p == null){
        return true; // open fallback
      }
      if(p.readRoles.isEmpty) return false; // closed (even owner) - adjust if needed
      if(role == 'owner') return true;
      return p.readRoles.contains(role);
    },
    loading: ()=> false, // while loading treat as no-access to avoid flashes (or true if preferred)
    error: (_, __)=> false,
  );
});

/// Access per specific action (read/create/update/delete)
enum ModuleAction { read, create, update, delete }

final moduleActionAccessProvider = Provider.family<bool, (String moduleKey, ModuleAction action)>((ref, tuple){
  final (moduleKey, action) = tuple;
  final user = ref.watch(appUserProvider);
  if(user == null) return false; final role = user.role; if(role==null) return false;
  final permsAsync = ref.watch(modulePermissionsProvider);
  return permsAsync.when(
    data: (perms){
      final p = perms[moduleKey];
      if(p == null){
        return true; // open fallback for unknown modules
      }
      if(role == 'owner') return true;
      List<String> list;
      switch(action){
        case ModuleAction.read: list = p.readRoles; break;
        case ModuleAction.create: list = p.createRoles; break;
        case ModuleAction.update: list = p.updateRoles; break;
        case ModuleAction.delete: list = p.deleteRoles; break;
      }
      if(list.isEmpty) return false; // closed
      return list.contains(role);
    },
    loading: ()=> false,
    error: (_, __)=> false,
  );
});

extension ModuleActionAccessRef on WidgetRef {
  bool can(String moduleKey, ModuleAction action) => watch(moduleActionAccessProvider((moduleKey, action)));
}

/// Convenience helper (optional) for imperative checks inside widgets:
/// ref.watch(hasModuleAccess('inventory'))
extension ModuleAccessRef on WidgetRef {
  bool watchModuleAccess(String key) => watch(moduleAccessProvider(key));
}
