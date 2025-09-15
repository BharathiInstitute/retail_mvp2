import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_providers.dart';

typedef RouteRedirect = FutureOr<String?> Function(BuildContext, GoRouterState);

RouteRedirect roleGuard({required UserRole requiredRole}) {
  return (BuildContext context, GoRouterState state) {
    final container = ProviderScope.containerOf(context);
    final role = container.read(userRoleProvider);
    if (role.index >= requiredRole.index) return null; // allow equal or higher
    return '/dashboard';
  };
}
