import 'package:flutter/material.dart';

// Consolidated Billing module in a single file.
// Includes BillingListScreen and all related helpers/models.

class BillingListScreen extends StatefulWidget {
	final String? invoiceId; // kept for router signature compatibility
	const BillingListScreen({super.key, this.invoiceId});

	@override
	State<BillingListScreen> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingListScreen> {
	// Demo data
	late List<BillingCustomer> customers;
	late List<BillingProduct> products;
	final List<Invoice> invoices = [];
	final List<CreditDebitNote> notes = [];

	// UI state
	Invoice? selected;
	String query = '';
	String? statusFilter; // Paid/Pending/Credit
	DateTimeRange? dateRange;

	bool taxInclusive = true;

	int nextInvoiceNumber = 1001; // auto-numbering demo

	@override
	void initState() {
		super.initState();
		customers = [
			BillingCustomer(name: 'Walk-in Customer'),
			BillingCustomer(name: 'Rahul Sharma'),
			BillingCustomer(name: 'Priya Singh'),
		];
		products = [
			BillingProduct(sku: 'SKU1001', name: 'Milk 1L', price: 55.0, taxPercent: 5),
			BillingProduct(sku: 'SKU2001', name: 'Shampoo 200ml', price: 120.0, taxPercent: 18),
			BillingProduct(sku: 'SKU3001', name: 'Biscuits 100g', price: 20.0, taxPercent: 12),
		];
		// Seed demo invoices
		invoices.addAll([
			_demoInvoice('1000', customers[1], [
				InvoiceItem(product: products[0], qty: 2),
				InvoiceItem(product: products[2], qty: 5),
			], status: 'Paid', date: DateTime.now().subtract(const Duration(days: 2)), inclusive: true),
			_demoInvoice('1000A', customers[2], [
				InvoiceItem(product: products[1], qty: 1),
			], status: 'Pending', date: DateTime.now().subtract(const Duration(days: 1)), inclusive: false),
		]);
		selected = invoices.first;
	}

	Invoice _demoInvoice(String no, BillingCustomer c, List<InvoiceItem> items, {required String status, required DateTime date, required bool inclusive}) {
		return Invoice(invoiceNo: no, customer: c, items: items, date: date, status: status, taxInclusive: inclusive);
	}

	// Helpers
	void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

	List<Invoice> get filteredInvoices {
		return invoices.where((inv) {
			final q = query.trim().toLowerCase();
			final matchesQuery = q.isEmpty || inv.invoiceNo.toLowerCase().contains(q) || inv.customer.name.toLowerCase().contains(q);
			final matchesStatus = statusFilter == null || inv.status == statusFilter;
			final matchesDate = dateRange == null || (inv.date.isAfter(dateRange!.start.subtract(const Duration(days: 1))) && inv.date.isBefore(dateRange!.end.add(const Duration(days: 1))));
			return matchesQuery && matchesStatus && matchesDate;
		}).toList();
	}

	void createInvoice() async {
		final inv = await showDialog<Invoice>(
			context: context,
			builder: (_) => _InvoiceEditor(
				customers: customers,
				products: products,
				startingNumber: nextInvoiceNumber,
				taxInclusive: taxInclusive,
			),
		);
		if (inv != null) {
			setState(() {
				invoices.add(inv);
				selected = inv;
				nextInvoiceNumber++;
			});
			_snack('Invoice ${inv.invoiceNo} created');
		}
	}

	void duplicateInvoice(Invoice inv) {
		final copy = inv.copyWith(invoiceNo: (nextInvoiceNumber++).toString(), date: DateTime.now(), status: 'Pending');
		setState(() {
			invoices.add(copy);
			selected = copy;
		});
		_snack('Invoice ${copy.invoiceNo} duplicated');
	}

	void reissueInvoice(Invoice inv) {
		duplicateInvoice(inv);
	}

	void saveToCloud(Invoice inv) {
		_snack('Saved to Firestore/Storage (demo)');
	}

	void addNote(Invoice inv) async {
		final note = await showDialog<CreditDebitNote>(
			context: context,
			builder: (_) => _NoteEditor(invoice: inv),
		);
		if (note != null) {
			setState(() => notes.add(note));
			_snack('${note.type.toUpperCase()} note created');
		}
	}

	List<CreditDebitNote> get notesForSelected => selected == null ? [] : notes.where((n) => n.invoiceNo == selected!.invoiceNo).toList();

	@override
	Widget build(BuildContext context) {
		final isWide = MediaQuery.of(context).size.width > 1100;
		return Padding(
			padding: const EdgeInsets.all(12.0),
			child: isWide ? _wideLayout() : _narrowLayout(),
		);
	}

	// Layouts
	Widget _wideLayout() {
		return Column(
			crossAxisAlignment: CrossAxisAlignment.start,
			children: [
				_searchFilterBar(),
				const SizedBox(height: 8),
				Expanded(
					child: Row(
						crossAxisAlignment: CrossAxisAlignment.start,
						children: [
							SizedBox(width: 400, child: _invoiceList()),
							const SizedBox(width: 12),
							Expanded(child: _invoiceDetails()),
						],
					),
				),
			],
		);
	}

	Widget _narrowLayout() {
		return ListView(
			children: [
				_searchFilterBar(),
				const SizedBox(height: 8),
				_invoiceList(height: 280),
				const SizedBox(height: 8),
				_invoiceDetails(),
			],
		);
	}

	// Search/Filter
	Widget _searchFilterBar() {
		return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
			ElevatedButton.icon(onPressed: createInvoice, icon: const Icon(Icons.add), label: const Text('New Invoice')),
			OutlinedButton.icon(onPressed: () => setState(() => taxInclusive = !taxInclusive), icon: const Icon(Icons.percent), label: Text(taxInclusive ? 'Tax Inclusive' : 'Tax Exclusive')),
			SizedBox(
				width: 260,
				child: TextField(
					decoration: const InputDecoration(labelText: 'Search (invoice no / customer)', prefixIcon: Icon(Icons.search)),
					onChanged: (v) => setState(() => query = v),
				),
			),
			DropdownButton<String>(
				value: statusFilter,
				hint: const Text('Status'),
				items: const [
					DropdownMenuItem(value: 'Paid', child: Text('Paid')),
					DropdownMenuItem(value: 'Pending', child: Text('Pending')),
					DropdownMenuItem(value: 'Credit', child: Text('Credit')),
				],
				onChanged: (v) => setState(() => statusFilter = v),
			),
			OutlinedButton.icon(
				onPressed: () async {
					final now = DateTime.now();
					final picked = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 1));
					if (picked != null) setState(() => dateRange = picked);
				},
				icon: const Icon(Icons.date_range),
				label: Text(dateRange == null ? 'Date Range' : '${_fmtDate(dateRange!.start)} → ${_fmtDate(dateRange!.end)}'),
			),
			OutlinedButton.icon(
				onPressed: () => setState(() {
					query = '';
					statusFilter = null;
					dateRange = null;
				}),
				icon: const Icon(Icons.clear),
				label: const Text('Clear'),
			),
		]);
	}

	// Invoice List
	Widget _invoiceList({double? height}) {
		final list = filteredInvoices;
		final listView = ListView.separated(
				itemCount: list.length,
				separatorBuilder: (_, __) => const Divider(height: 1),
				itemBuilder: (_, i) {
					final inv = list[i];
					return ListTile(
						selected: inv == selected,
						onTap: () => setState(() => selected = inv),
						title: Text('Invoice #${inv.invoiceNo} • ${inv.customer.name}'),
						subtitle: Text('${_fmtDate(inv.date)} • ₹${inv.total(taxInclusive: taxInclusive).toStringAsFixed(2)}'),
						trailing: _statusChip(inv.status),
					);
				},
			);
		final content = Card(
			child: Scrollbar(
				thumbVisibility: true,
				child: listView,
			),
		);
		return height != null ? SizedBox(height: height, child: content) : content;
	}

	// Invoice Details & Actions
	Widget _invoiceDetails() {
		if (selected == null) return const Card(child: SizedBox(height: 240, child: Center(child: Text('Select an invoice'))));
		final inv = selected!;
		final gst = inv.gstBreakup(taxInclusive: taxInclusive);
		return Card(
			child: Scrollbar(
				thumbVisibility: true,
				child: SingleChildScrollView(
					padding: const EdgeInsets.all(12.0),
					child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Row(children: [
						Expanded(child: Text('Invoice #${inv.invoiceNo}  •  ${_fmtDateTime(inv.date)}', style: const TextStyle(fontWeight: FontWeight.bold))),
						DropdownButton<String>(
							value: inv.status,
							items: const [
								DropdownMenuItem(value: 'Paid', child: Text('Paid')),
								DropdownMenuItem(value: 'Pending', child: Text('Pending')),
								DropdownMenuItem(value: 'Credit', child: Text('Credit')),
							],
							onChanged: (v) => setState(() {
								final updated = inv.copyWith(status: v ?? inv.status);
								selected = updated;
								_replaceInvoice(updated);
							}),
						),
					]),
					const SizedBox(height: 8),
					SingleChildScrollView(
						scrollDirection: Axis.horizontal,
						child: DataTable(columns: const [
							DataColumn(label: Text('SKU')),
							DataColumn(label: Text('Item')),
							DataColumn(label: Text('Qty')),
							DataColumn(label: Text('Price')),
							DataColumn(label: Text('GST %')),
							DataColumn(label: Text('Line Total')),
						], rows: [
							for (final it in inv.items)
								DataRow(cells: [
									DataCell(Text(it.product.sku)),
									DataCell(Text(it.product.name)),
									DataCell(Text(it.qty.toString())),
									DataCell(Text('₹${it.product.price.toStringAsFixed(2)}')),
									DataCell(Text('${it.product.taxPercent}%')),
									DataCell(Text('₹${it.lineTotal(taxInclusive: taxInclusive).toStringAsFixed(2)}')),
								]),
						]),
					),
					const Divider(),
					Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.spaceBetween, children: [
						Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
							const Text('GST Breakup'),
							_kv('CGST', gst.cgst),
							_kv('SGST', gst.sgst),
							_kv('IGST', gst.igst),
							const SizedBox(height: 6),
							_kv('Subtotal', inv.subtotal(taxInclusive: taxInclusive)),
							_kv('Tax Total', gst.totalTax),
							const Divider(),
							_kv('Grand Total', inv.total(taxInclusive: taxInclusive), bold: true),
						]),
						Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
							const Text('Actions'),
							Wrap(spacing: 8, children: [
								ElevatedButton.icon(onPressed: () => _snack('PDF generated (demo)'), icon: const Icon(Icons.picture_as_pdf), label: const Text('Generate PDF')),
								OutlinedButton.icon(onPressed: () => _snack('Printing...'), icon: const Icon(Icons.print), label: const Text('Print')),
								OutlinedButton.icon(onPressed: () => _snack('Email sent'), icon: const Icon(Icons.email), label: const Text('Email')),
								OutlinedButton.icon(onPressed: () => saveToCloud(inv), icon: const Icon(Icons.cloud_upload), label: const Text('Save to Cloud')),
								OutlinedButton.icon(onPressed: () => duplicateInvoice(inv), icon: const Icon(Icons.copy), label: const Text('Duplicate')),
								OutlinedButton.icon(onPressed: () => reissueInvoice(inv), icon: const Icon(Icons.replay), label: const Text('Re-issue')),
								OutlinedButton.icon(onPressed: () => addNote(inv), icon: const Icon(Icons.edit_note), label: const Text('Credit/Debit Note')),
							]),
						]),
					]),
					const Divider(),
					const Text('Notes (Credit/Debit)'),
					_notesList(notesForSelected),
					]),
				),
			),
		);
	}

	Widget _notesList(List<CreditDebitNote> list) {
		if (list.isEmpty) return const Padding(padding: EdgeInsets.all(8), child: Text('No notes'));
		return Card(
			child: ListView.separated(
				shrinkWrap: true,
				physics: const NeverScrollableScrollPhysics(),
				itemCount: list.length,
				separatorBuilder: (_, __) => const Divider(height: 1),
				itemBuilder: (_, i) {
					final n = list[i];
					return ListTile(
						title: Text('${n.type.toUpperCase()} • ₹${n.amount.toStringAsFixed(2)}'),
						subtitle: Text('Reason: ${n.reason} • Date: ${_fmtDateTime(n.date)}'),
					);
				},
			),
		);
	}

	void _replaceInvoice(Invoice updated) {
		final idx = invoices.indexWhere((e) => e.invoiceNo == updated.invoiceNo);
		if (idx >= 0) invoices[idx] = updated;
	}

	// Small UI helpers
	Widget _kv(String label, double value, {bool bold = false}) {
		final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal);
		return Padding(
			padding: const EdgeInsets.symmetric(vertical: 2.0),
			child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label, style: style), Text('₹${value.toStringAsFixed(2)}', style: style)]),
		);
	}

	Widget _statusChip(String status) {
		Color c = Colors.grey;
		if (status == 'Paid') c = Colors.green;
		if (status == 'Pending') c = Colors.orange;
		if (status == 'Credit') c = Colors.purple;
		return Chip(label: Text(status), backgroundColor: c.withValues(alpha: 0.15));
	}
}

// Invoice editor dialog for creating a new invoice
class _InvoiceEditor extends StatefulWidget {
	final List<BillingCustomer> customers;
	final List<BillingProduct> products;
	final int startingNumber;
	final bool taxInclusive;
	const _InvoiceEditor({required this.customers, required this.products, required this.startingNumber, required this.taxInclusive});

	@override
	State<_InvoiceEditor> createState() => _InvoiceEditorState();
}

class _InvoiceEditorState extends State<_InvoiceEditor> {
	BillingCustomer? customer;
	final List<InvoiceItem> items = [];
	bool taxInclusive = true;

	@override
	void initState() {
		super.initState();
		customer = widget.customers.first;
		items.addAll([
			InvoiceItem(product: widget.products[0], qty: 1),
			InvoiceItem(product: widget.products[2], qty: 2),
		]);
		taxInclusive = widget.taxInclusive;
	}

	@override
	Widget build(BuildContext context) {
		final subtotal = items.fold<double>(0, (s, it) => s + it.lineSubtotal(taxInclusive: taxInclusive));
		final gst = Invoice.gstBreakupFor(items, taxInclusive: taxInclusive);
		final total = items.fold<double>(0, (s, it) => s + it.lineTotal(taxInclusive: taxInclusive));
		return AlertDialog(
			title: const Text('New Invoice'),
			content: SizedBox(
				width: 640,
				child: Column(
					mainAxisSize: MainAxisSize.min,
					crossAxisAlignment: CrossAxisAlignment.start,
					children: [
						Row(children: [
							Expanded(
								child: DropdownButtonFormField<BillingCustomer>(
									initialValue: customer,
									items: [for (final c in widget.customers) DropdownMenuItem(value: c, child: Text(c.name))],
									onChanged: (v) => setState(() => customer = v),
									decoration: const InputDecoration(labelText: 'Customer'),
								),
							),
							const SizedBox(width: 8),
							Expanded(
								child: SwitchListTile(
									value: taxInclusive,
									onChanged: (v) => setState(() => taxInclusive = v),
									title: const Text('Tax Inclusive'),
								),
							),
						]),
						const SizedBox(height: 8),
						Card(
							child: Column(children: [
								for (final it in items.asMap().entries)
									ListTile(
										title: Text(it.value.product.name),
										subtitle: Text('₹${it.value.product.price.toStringAsFixed(2)} • GST ${it.value.product.taxPercent}%'),
										trailing: SizedBox(
											width: 160,
											child: Row(children: [
												IconButton(
													icon: const Icon(Icons.remove),
													onPressed: () => setState(
														() => items[it.key] = it.value.copyWith(qty: (it.value.qty - 1).clamp(1, 999).toInt()),
													),
												),
												Text(it.value.qty.toString()),
												IconButton(icon: const Icon(Icons.add), onPressed: () => setState(() => items[it.key] = it.value.copyWith(qty: it.value.qty + 1))),
											]),
										),
									),
								ListTile(
									leading: const Icon(Icons.add_circle_outline),
									title: const Text('Add Item'),
									onTap: () async {
										final p = await showDialog<BillingProduct>(
											context: context,
											builder: (_) => _ProductPicker(products: widget.products),
										);
										if (p != null) setState(() => items.add(InvoiceItem(product: p, qty: 1)));
									},
								)
							]),
						),
						const SizedBox(height: 8),
						Align(alignment: Alignment.centerRight, child: Text('Subtotal: ₹${subtotal.toStringAsFixed(2)}')),
						Align(alignment: Alignment.centerRight, child: Text('CGST: ₹${gst.cgst.toStringAsFixed(2)}  SGST: ₹${gst.sgst.toStringAsFixed(2)}  IGST: ₹${gst.igst.toStringAsFixed(2)}')),
						Align(alignment: Alignment.centerRight, child: Text('Total: ₹${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold))),
					],
				),
			),
			actions: [
				TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
				ElevatedButton(
					onPressed: () {
						final inv = Invoice(
							invoiceNo: widget.startingNumber.toString(),
							customer: customer!,
							items: List.of(items),
							date: DateTime.now(),
							status: 'Pending',
							taxInclusive: taxInclusive,
						);
						Navigator.pop(context, inv);
					},
					child: const Text('Create'),
				),
			],
		);
	}
}

class _ProductPicker extends StatelessWidget {
	final List<BillingProduct> products;
	const _ProductPicker({required this.products});
	@override
	Widget build(BuildContext context) {
		return SimpleDialog(
			title: const Text('Add Product'),
			children: [
				SizedBox(
					width: 360,
					height: 320,
					child: ListView.separated(
						itemCount: products.length,
						separatorBuilder: (_, __) => const Divider(height: 1),
						itemBuilder: (_, i) => ListTile(
							title: Text(products[i].name),
							subtitle: Text('₹${products[i].price.toStringAsFixed(2)} • GST ${products[i].taxPercent}%'),
							onTap: () => Navigator.pop(context, products[i]),
						),
					),
				)
			],
		);
	}
}

// Credit/Debit Note Editor
class _NoteEditor extends StatefulWidget {
	final Invoice invoice;
	const _NoteEditor({required this.invoice});

	@override
	State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
	String type = 'credit';
	final amountCtrl = TextEditingController(text: '0');
	final reasonCtrl = TextEditingController();
	@override
	Widget build(BuildContext context) {
		return AlertDialog(
			title: Text('New ${type.toUpperCase()} Note'),
			content: SizedBox(
				width: 420,
				child: Column(
					mainAxisSize: MainAxisSize.min,
					children: [
						DropdownButtonFormField<String>(
							initialValue: type,
							items: const [DropdownMenuItem(value: 'credit', child: Text('Credit')), DropdownMenuItem(value: 'debit', child: Text('Debit'))],
							onChanged: (v) => setState(() => type = v ?? 'credit'),
							decoration: const InputDecoration(labelText: 'Type'),
						),
						TextFormField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount ₹')),
						TextFormField(controller: reasonCtrl, decoration: const InputDecoration(labelText: 'Reason')),
					],
				),
			),
			actions: [
				TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
				ElevatedButton(
					onPressed: () {
						final note = CreditDebitNote(
							invoiceNo: widget.invoice.invoiceNo,
							type: type,
							amount: double.tryParse(amountCtrl.text) ?? 0,
							reason: reasonCtrl.text.trim(),
							date: DateTime.now(),
						);
						Navigator.pop(context, note);
					},
					child: const Text('Create'),
				)
			],
		);
	}
}

// Data models and GST helpers
class BillingCustomer { final String name; BillingCustomer({required this.name}); }

class BillingProduct {
	final String sku; final String name; final double price; final int taxPercent;
	BillingProduct({required this.sku, required this.name, required this.price, required this.taxPercent});
}

class InvoiceItem {
	final BillingProduct product; final int qty;
	InvoiceItem({required this.product, required this.qty});
	InvoiceItem copyWith({BillingProduct? product, int? qty}) => InvoiceItem(product: product ?? this.product, qty: qty ?? this.qty);

	double lineSubtotal({required bool taxInclusive}) {
		if (taxInclusive) {
			final base = product.price / (1 + product.taxPercent / 100);
			return base * qty;
		} else {
			return product.price * qty;
		}
	}

	double lineTax({required bool taxInclusive}) {
		final base = lineSubtotal(taxInclusive: taxInclusive);
		return base * (product.taxPercent / 100);
	}

	double lineTotal({required bool taxInclusive}) {
		return lineSubtotal(taxInclusive: taxInclusive) + lineTax(taxInclusive: taxInclusive);
	}
}

class GSTBreakup {
	final double cgst; final double sgst; final double igst;
	const GSTBreakup({required this.cgst, required this.sgst, required this.igst});
	double get totalTax => cgst + sgst + igst;
}

class Invoice {
	final String invoiceNo; final BillingCustomer customer; final List<InvoiceItem> items; final DateTime date; final String status; final bool taxInclusive;
	Invoice({required this.invoiceNo, required this.customer, required this.items, required this.date, required this.status, required this.taxInclusive});

	Invoice copyWith({String? invoiceNo, BillingCustomer? customer, List<InvoiceItem>? items, DateTime? date, String? status, bool? taxInclusive}) {
		final copy = Invoice(
			invoiceNo: invoiceNo ?? this.invoiceNo,
			customer: customer ?? this.customer,
			items: items ?? this.items,
			date: date ?? this.date,
			status: status ?? this.status,
			taxInclusive: taxInclusive ?? this.taxInclusive,
		);
		return copy;
	}

	double subtotal({required bool taxInclusive}) => items.fold(0.0, (s, it) => s + it.lineSubtotal(taxInclusive: taxInclusive));
	double total({required bool taxInclusive}) => items.fold(0.0, (s, it) => s + it.lineTotal(taxInclusive: taxInclusive));

	static GSTBreakup gstBreakupFor(List<InvoiceItem> items, {required bool taxInclusive}) {
		double cgst = 0, sgst = 0, igst = 0;
		for (final it in items) {
			final tax = it.lineTax(taxInclusive: taxInclusive);
			// Demo: split equally between CGST/SGST for intra-state; IGST=0. Adjust as needed.
			cgst += tax / 2;
			sgst += tax / 2;
		}
		return GSTBreakup(cgst: cgst, sgst: sgst, igst: igst);
	}

	GSTBreakup gstBreakup({required bool taxInclusive}) => gstBreakupFor(items, taxInclusive: taxInclusive);
}

class CreditDebitNote {
	final String invoiceNo; final String type; // credit|debit
	final double amount; final String reason; final DateTime date;
	CreditDebitNote({required this.invoiceNo, required this.type, required this.amount, required this.reason, required this.date});
}

// Helpers
String _fmtDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _fmtDateTime(DateTime d) => '${_fmtDate(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
