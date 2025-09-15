# Retail ERP MVP – Flutter Shell

Modular, scalable Flutter 3.x app shell with Riverpod, GoRouter, Material 3, and Firebase placeholders.

## Tech stack
- Flutter 3.x (null-safety), Material 3, light/dark
- State: flutter_riverpod
- Routing: go_router (nested, shell, guards)
- Backend: Firebase placeholders (Auth, Firestore, Storage, Functions) – mocked for now
- Platforms: Mobile, Tablet, Web (responsive layouts)

## Modules
- Dashboard
- POS
- Inventory
- Billing
- CRM
- Accounting
- Loyalty
- Admin / User Management

## Structure
```
lib/
	app.dart                # MaterialApp.router + themes
	core/
		router/app_router.dart
		widgets/app_shell.dart, common_widgets.dart
		providers/auth_providers.dart
		models/models.dart
		services/mock_services.dart
		guards/role_guard.dart
	features/
		<feature>/{ui,models,services}
```

## Run
1) Install deps
2) Run on any device/web

Notes: Firebase is not initialized. Mock providers make the UI render without backend. Replace mocks gradually with real services.
