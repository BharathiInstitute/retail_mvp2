import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retail_mvp2/app_shell.dart';
import 'package:retail_mvp2/core/auth/auth.dart';
import 'package:retail_mvp2/core/permissions.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// Simple fake AuthRepository to avoid Firebase initialization in widget tests.
class _FakeAuthRepo implements AuthRepository {
  final AuthUser _user = const AuthUser(uid: 'test-uid', email: 'test@example.com');
  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _user;
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<void> createUserWithEmailPassword({required String email, required String password}) async {}

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {}

  @override
  Future<void> signInWithEmailPassword({required String email, required String password}) async {}

  @override
  Future<void> signOut() async {}
}

void main() {
  testWidgets('App loads dashboard shell', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_FakeAuthRepo()),
          // Simplify routing in tests to avoid async redirects/races.
          appRouterProvider.overrideWithValue(GoRouter(
            initialLocation: '/',
            routes: [
              GoRoute(
                path: '/',
                builder: (_, __) => const _TestHome(),
              ),
            ],
          )),
          // Avoid hitting Firestore in tests: provide immediate streams.
          permissionsProvider.overrideWith((ref) =>
              Stream<UserPermissions>.value(const UserPermissions({
                ScreenKeys.dashboard: ScreenPerm(view: true),
                ScreenKeys.posMain: ScreenPerm(view: true),
                ScreenKeys.invProducts: ScreenPerm(view: true),
              }))),
          ownerProvider.overrideWith((ref) => Stream<bool>.value(false)),
        ],
        child: const MyApp(),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Retail ERP MVP'), findsOneWidget);
  });
}

class _TestHome extends StatelessWidget {
  const _TestHome();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Retail ERP MVP')),
      body: const SizedBox.shrink(),
    );
  }
}
