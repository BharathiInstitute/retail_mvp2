import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthProfile {
  final User? user;
  final Map<String, dynamic> claims;
  final Map<String, dynamic> storeRoles; // storeId -> role
  final bool active;
  final String? lastStoreId;
  const AuthProfile({
    required this.user,
    required this.claims,
    required this.storeRoles,
    required this.active,
    required this.lastStoreId,
  });
}

final authUserProvider = StreamProvider<AuthProfile>((ref) async* {
  final controller = StreamController<AuthProfile>();
  void emit(User? u, Map<String,dynamic>? tokenResult) {
    final claims = tokenResult?['claims'] ?? {};
    final sr = (claims['storeRoles'] is Map) ? Map<String,dynamic>.from(claims['storeRoles']) : <String,dynamic>{};
    final active = claims['active'] != false; // default true
    final lastStoreId = claims['lastStoreId'] as String?;
    controller.add(AuthProfile(user: u, claims: claims, storeRoles: sr, active: active, lastStoreId: lastStoreId));
  }
  final auth = FirebaseAuth.instance;
  auth.authStateChanges().listen((u) async {
    if (u == null) { emit(null, null); return; }
    final idTokenResult = await u.getIdTokenResult();
    emit(u, {'claims': idTokenResult.claims});
  });
  yield* controller.stream;
});
