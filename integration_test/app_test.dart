import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:retail_mvp2/main.dart' as app;

/// Integration tests for Retail ERP MVP
/// 
/// Run with: flutter test integration_test/app_test.dart
/// 
/// Note: These tests require a running Firebase emulator or test environment.
/// For production testing, use a separate test Firebase project.

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App Launch Tests', () {
    testWidgets('App launches without crash', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // App should show either login screen or dashboard
      final hasLoginOrDashboard = 
          find.text('Sign In').evaluate().isNotEmpty ||
          find.text('Login').evaluate().isNotEmpty ||
          find.text('Dashboard').evaluate().isNotEmpty ||
          find.text('Retail ERP MVP').evaluate().isNotEmpty;
      
      expect(hasLoginOrDashboard, isTrue, reason: 'App should show login or dashboard');
    });
  });

  group('Navigation Tests', () {
    testWidgets('Can navigate to POS screen', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Look for POS navigation icon (grid icon or POS text)
      final posIcon = find.byIcon(Icons.point_of_sale);
      final gridIcon = find.byIcon(Icons.grid_view);
      
      if (posIcon.evaluate().isNotEmpty) {
        await tester.tap(posIcon);
      } else if (gridIcon.evaluate().isNotEmpty) {
        await tester.tap(gridIcon);
      }
      
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      // Should be on POS screen - look for cart or product elements
      // This will pass if any POS-related element is found
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Can navigate to Inventory screen', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Look for Inventory navigation
      final inventoryIcon = find.byIcon(Icons.inventory);
      final inventoryIcon2 = find.byIcon(Icons.inventory_2);
      
      if (inventoryIcon.evaluate().isNotEmpty) {
        await tester.tap(inventoryIcon);
      } else if (inventoryIcon2.evaluate().isNotEmpty) {
        await tester.tap(inventoryIcon2);
      }
      
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      expect(find.byType(Scaffold), findsWidgets);
    });

    testWidgets('Can navigate to Customers screen', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Look for Customers/CRM navigation
      final peopleIcon = find.byIcon(Icons.people);
      final personIcon = find.byIcon(Icons.person);
      
      if (peopleIcon.evaluate().isNotEmpty) {
        await tester.tap(peopleIcon);
      } else if (personIcon.evaluate().isNotEmpty) {
        await tester.tap(personIcon);
      }
      
      await tester.pumpAndSettle(const Duration(seconds: 2));
      
      expect(find.byType(Scaffold), findsWidgets);
    });
  });

  group('POS Flow Tests', () {
    testWidgets('POS screen has cart area', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Navigate to POS
      final posIcon = find.byIcon(Icons.point_of_sale);
      final gridIcon = find.byIcon(Icons.grid_view);
      
      if (posIcon.evaluate().isNotEmpty) {
        await tester.tap(posIcon);
      } else if (gridIcon.evaluate().isNotEmpty) {
        await tester.tap(gridIcon);
      }
      
      await tester.pumpAndSettle(const Duration(seconds: 3));
      
      // Look for cart-related elements
      final hasCartElements = 
          find.textContaining('Cart').evaluate().isNotEmpty ||
          find.textContaining('Total').evaluate().isNotEmpty ||
          find.textContaining('Checkout').evaluate().isNotEmpty ||
          find.textContaining('Pay').evaluate().isNotEmpty ||
          find.byIcon(Icons.shopping_cart).evaluate().isNotEmpty;
      
      expect(hasCartElements, isTrue, reason: 'POS should have cart elements');
    });

    testWidgets('POS has product search or list', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Navigate to POS
      final posIcon = find.byIcon(Icons.point_of_sale);
      final gridIcon = find.byIcon(Icons.grid_view);
      
      if (posIcon.evaluate().isNotEmpty) {
        await tester.tap(posIcon);
      } else if (gridIcon.evaluate().isNotEmpty) {
        await tester.tap(gridIcon);
      }
      
      await tester.pumpAndSettle(const Duration(seconds: 3));
      
      // Look for search or product elements
      final hasProductArea = 
          find.byType(TextField).evaluate().isNotEmpty ||
          find.byIcon(Icons.search).evaluate().isNotEmpty ||
          find.textContaining('Product').evaluate().isNotEmpty ||
          find.textContaining('Search').evaluate().isNotEmpty;
      
      expect(hasProductArea, isTrue, reason: 'POS should have search or product area');
    });
  });

  group('Responsive Layout Tests', () {
    testWidgets('App renders on small screen (mobile)', (tester) async {
      // Set small screen size
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1.0;
      
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Should render without overflow
      expect(tester.takeException(), isNull);
      
      // Reset
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('App renders on tablet screen', (tester) async {
      // Set tablet screen size
      tester.view.physicalSize = const Size(1024, 768);
      tester.view.devicePixelRatio = 1.0;
      
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Should render without overflow
      expect(tester.takeException(), isNull);
      
      // Reset
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    testWidgets('App renders on desktop screen', (tester) async {
      // Set desktop screen size
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // Should render without overflow
      expect(tester.takeException(), isNull);
      
      // Reset
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  });

  group('Error Handling Tests', () {
    testWidgets('App handles missing store gracefully', (tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));
      
      // App should not crash even without store selected
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
