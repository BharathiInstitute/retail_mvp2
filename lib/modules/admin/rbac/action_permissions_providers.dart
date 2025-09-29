import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'admin_rbac_providers.dart';

// Collection name for fine-grained action permissions.
// Each document represents one action row in the matrix.
// Doc shape:
// {
//   actionKey: 'jobs.create',          // unique stable key
//   label: 'Create new job and stages',
//   category: 'Jobs management',       // grouping header
//   categoryOrder: 10,                 // ordering for categories
//   order: 10,                         // ordering within category
//   roles: { owner:true, manager:true, accountant:false, cashier:false, clerk:false },
//   createdAt, updatedAt
// }
// Only admins (manageUsers || editSettings) can mutate (enforced client + add rules later).

final _actionPermsColl = FirebaseFirestore.instance.collection('permissions_actions');

class ActionPermissionRow {
  final String id;
  final String actionKey;
  final String label;
  final String category;
  final int categoryOrder;
  final int order;
  final Map<String,bool> roles;
  ActionPermissionRow({required this.id, required this.actionKey, required this.label, required this.category, required this.categoryOrder, required this.order, required this.roles});
}

final actionPermissionsProvider = StreamProvider<List<ActionPermissionRow>>((ref){
  return _actionPermsColl.snapshots().map((snap){
    return snap.docs.map((d){
      final data = d.data();
      return ActionPermissionRow(
        id: d.id,
        actionKey: (data['actionKey'] ?? d.id) as String,
        label: (data['label'] ?? d.id) as String,
        category: (data['category'] ?? 'General') as String,
        categoryOrder: (data['categoryOrder'] ?? 1000) as int,
        order: (data['order'] ?? 1000) as int,
        roles: ((data['roles'] ?? const <String,dynamic>{}) as Map<String,dynamic>).map((k,v)=> MapEntry(k, v == true)),
      );
    }).toList()..sort((a,b){
      final c = a.categoryOrder.compareTo(b.categoryOrder);
      if(c!=0) return c;
      final cat = a.category.toLowerCase().compareTo(b.category.toLowerCase());
      if(cat!=0) return cat;
      return a.order.compareTo(b.order);
    });
  });
});

/// Derived structure grouped by category.
class ActionPermissionCategoryGroup {
  final String category; final List<ActionPermissionRow> rows; final int order;
  ActionPermissionCategoryGroup(this.category, this.rows, this.order);
}

final actionPermissionGroupsProvider = Provider<List<ActionPermissionCategoryGroup>>((ref){
  final async = ref.watch(actionPermissionsProvider);
  return async.maybeWhen(
    data: (rows){
      final map = <String,List<ActionPermissionRow>>{}; final orders = <String,int>{};
      for(final r in rows){
        map.putIfAbsent(r.category, ()=>[]).add(r);
        orders[r.category] = r.categoryOrder;
      }
      return map.entries.map((e){
        final list = e.value..sort((a,b)=> a.order.compareTo(b.order));
        return ActionPermissionCategoryGroup(e.key, list, orders[e.key] ?? 1000);
      }).toList()..sort((a,b)=> a.order.compareTo(b.order));
    },
    orElse: ()=> const <ActionPermissionCategoryGroup>[]
  );
});

// Helper to check access for an actionKey.
final actionAccessProvider = Provider.family<bool, String>((ref, actionKey){
  final user = ref.watch(appUserProvider); if(user==null) return false; final role = user.role; if(role==null) return false;
  final rowsAsync = ref.watch(actionPermissionsProvider);
  return rowsAsync.when(
    data: (rows){
      final r = rows.firstWhere((e)=> e.actionKey == actionKey, orElse: ()=> ActionPermissionRow(id:'', actionKey:'', label:'', category:'', categoryOrder:0, order:0, roles: const {}));
      if(r.actionKey.isEmpty) return true; // default open if no row
      if(role=='owner') return true;
      return r.roles[role] == true;
    },
    loading: ()=> false,
    error: (_, __)=> false,
  );
});
