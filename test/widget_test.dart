import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:retail_mvp2/app_shell.dart';

void main() {
  testWidgets('App loads dashboard shell', (tester) async {
  await tester.pumpWidget(const ProviderScope(child: MyApp()));
    await tester.pumpAndSettle();
    expect(find.text('Retail ERP MVP'), findsOneWidget);
  });
}
