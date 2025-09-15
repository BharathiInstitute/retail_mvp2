import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

enum UserRole { admin, manager, cashier, viewer }

class AuthUser {
  final String uid;
  final String? displayName;
  final String? email;
  final UserRole role;
  const AuthUser({required this.uid, this.displayName, this.email, this.role = UserRole.viewer});
}

/// Mock Auth repository to simulate Firebase Auth state.
class MockAuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _current;

  Stream<AuthUser?> get stream => _controller.stream;
  AuthUser? get currentUser => _current;

  Future<void> signInAnonymously() async {
    _current = const AuthUser(uid: 'anon', displayName: 'Guest', role: UserRole.viewer);
    _controller.add(_current);
  }

  Future<void> signInAsAdmin() async {
    _current = const AuthUser(uid: 'admin1', displayName: 'Admin', email: 'admin@example.com', role: UserRole.admin);
    _controller.add(_current);
  }

  Future<void> signOut() async {
    _current = null;
    _controller.add(null);
  }

  void dispose() {
    _controller.close();
  }
}

final authRepositoryProvider = Provider<MockAuthRepository>((ref) {
  final repo = MockAuthRepository();
  ref.onDispose(repo.dispose);
  return repo;
});

class AuthStateNotifier extends StateNotifier<AuthUser?> {
  final MockAuthRepository repo;
  late final StreamSubscription<AuthUser?> _sub;

  AuthStateNotifier(this.repo) : super(repo.currentUser) {
    _sub = repo.stream.listen((user) => state = user);
    // Auto sign-in anonymously for shell
    repo.signInAnonymously();
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

final userRoleProvider = Provider<UserRole>((ref) {
  final user = ref.watch(authStateProvider);
  return user?.role ?? UserRole.viewer;
});
