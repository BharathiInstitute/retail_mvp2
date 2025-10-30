import 'package:flutter/material.dart';
import 'package:retail_mvp2/modules/invoices/sales_invoices.dart' show SalesInvoicesScreen;

/// Tablet Sales screen that shows the same list UI as desktop.
/// Reuses InvoicesListScreen so data and visuals are identical.
class SalesTabPage extends StatelessWidget {
	const SalesTabPage({super.key});

	@override
	Widget build(BuildContext context) {
		// Reuse the same screen as desktop; rely on defaults so alignment stays identical
		return const SalesInvoicesScreen();
	}
}
