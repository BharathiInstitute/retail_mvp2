import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;

class AuthUser {
  final String uid;
  final String? displayName;
  final String? email;
  const AuthUser({required this.uid, this.displayName, this.email});
}

abstract class AuthRepository {
  Stream<AuthUser?> authStateChanges();
  AuthUser? get currentUser;
  Future<void> signInWithEmailPassword({required String email, required String password});
  Future<void> createUserWithEmailPassword({required String email, required String password});
  Future<void> sendPasswordResetEmail({required String email});
  Future<void> signOut();
}

class FirebaseAuthRepository implements AuthRepository {
  final fb.FirebaseAuth _auth;
  FirebaseAuthRepository({fb.FirebaseAuth? auth}) : _auth = auth ?? fb.FirebaseAuth.instance;

  @override
  Stream<AuthUser?> authStateChanges() => _auth.authStateChanges().map(
        (u) => u == null ? null : AuthUser(uid: u.uid, displayName: u.displayName, email: u.email),
      );

  @override
  AuthUser? get currentUser {
    final u = _auth.currentUser;
    return u == null ? null : AuthUser(uid: u.uid, displayName: u.displayName, email: u.email);
  }

  @override
  Future<void> signInWithEmailPassword({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> createUserWithEmailPassword({required String email, required String password}) async {
    await _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) => _auth.sendPasswordResetEmail(email: email);

  @override
  Future<void> signOut() => _auth.signOut();
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => FirebaseAuthRepository());

class AuthStateNotifier extends StateNotifier<AuthUser?> {
  final AuthRepository repo;
  late final StreamSubscription<AuthUser?> _sub;

  AuthStateNotifier(this.repo) : super(repo.currentUser) {
    _sub = repo.authStateChanges().listen((user) => state = user);
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthUser?>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  return AuthStateNotifier(repo);
});
