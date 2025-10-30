  
import 'package:flutter/material.dart';

import 'package:flutter/material.dart';
/*

import 'pos.dart';

// Search + barcode + scanner toggle card
class PosSearchAndScanCard extends StatelessWidget {
	final TextEditingController barcodeController;
	final TextEditingController searchController;
	// Optional: customer search field shown above the barcode/search field
	final TextEditingController? customerSearchController;
	final List<Customer>? customerSuggestions;
	final ValueChanged<Customer>? onCustomerSelected;
	final VoidCallback? onCustomerQueryChanged;
	final String? selectedCustomerName;
	final bool scannerActive;
	final bool scannerConnected;
	final ValueChanged<bool> onScannerToggle;
	final VoidCallback onBarcodeSubmitted;
	final VoidCallback onSearchChanged;
	// Optional customer dropdown to place beside the barcode field
	final Widget? customerSelector;
	// Optional action area to the left of the barcode/search field (e.g., All/Favorite toggles)
	final Widget? barcodeTrailing;

	const PosSearchAndScanCard({
		super.key,
		required this.barcodeController,
		required this.searchController,
		this.customerSearchController,
		this.customerSuggestions,
		this.onCustomerSelected,
		this.onCustomerQueryChanged,
		this.selectedCustomerName,
		required this.scannerActive,
		required this.scannerConnected,
		required this.onScannerToggle,
		required this.onBarcodeSubmitted,
		required this.onSearchChanged,
		this.customerSelector,
		this.barcodeTrailing,
	});

	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12.0),
				child: Align(
					alignment: Alignment.centerLeft,
					child: ConstrainedBox(
						constraints: const BoxConstraints(maxWidth: 520),
						child: Column(
							crossAxisAlignment: CrossAxisAlignment.start,
							children: [
								// Customer search field (optional) with trailing icons + scanner
								if (customerSearchController != null) ...[
									Row(
										children: [
											Expanded(
												child: TextField(
													controller: customerSearchController,
													decoration: const InputDecoration(
														labelText: 'Search customer',
														prefixIcon: Icon(Icons.person_search_outlined),
													),
													onChanged: (_) => onCustomerQueryChanged?.call(),
												),
											),
											if (customerSelector != null) ...[
												const SizedBox(width: 8),
												Flexible(flex: 0, child: customerSelector!),
											],
											const SizedBox(width: 8),
											_ScannerToggle(
												active: scannerActive,
												connected: scannerConnected,
												onChanged: onScannerToggle,
											),
										],
									),
									// Inline suggestions list (shows only when user is actively searching)
									if ((customerSuggestions ?? const <Customer>[]).isNotEmpty &&
											((customerSearchController?.text.trim() ?? '').isNotEmpty) &&
											((customerSearchController?.text.trim() ?? '').length >= 2) &&
											((customerSearchController?.text.trim() ?? '') != (selectedCustomerName ?? '').trim()))
										Container(
											margin: const EdgeInsets.only(top: 6.0, bottom: 6.0),
											constraints: const BoxConstraints(maxHeight: 180),
											decoration: BoxDecoration(
												border: Border.all(color: Theme.of(context).dividerColor),
												borderRadius: BorderRadius.circular(8),
												color: Theme.of(context).colorScheme.surface,
											),
											child: ListView.builder(
												itemCount: customerSuggestions!.length,
												itemBuilder: (_, i) {
													final c = customerSuggestions![i];
													return ListTile(
														leading: const Icon(Icons.person_outline),
														dense: true,
														title: Text(c.name, overflow: TextOverflow.ellipsis),
														onTap: () {
														// Fill the field with selected customer's name and notify parent
														customerSearchController!.text = c.name;
														onCustomerSelected?.call(c);
														// Hide keyboard and suggestion list
														FocusScope.of(context).unfocus();
													},
												);
											},
										),
									),
								],
								Row(
									children: [
										// Optional actions on the left side
										if (barcodeTrailing != null) ...[
											Flexible(flex: 0, child: barcodeTrailing!),
											const SizedBox(width: 8),
										],
										Expanded(
											child: TextField(
												controller: searchController,
												decoration: const InputDecoration(
													labelText: 'Barcode / SKU or Search',
													prefixIcon: Icon(Icons.qr_code_scanner),
												),
												onSubmitted: (_) => onBarcodeSubmitted(),
												onChanged: (_) => onSearchChanged(),
											),
										),
										// If there's no customer row above, allow selector + scanner here
										if (customerSearchController == null && customerSelector != null) ...[
											const SizedBox(width: 8),
											Flexible(flex: 0, child: customerSelector!),
										],
										if (customerSearchController == null) ...[
											const SizedBox(width: 8),
											_ScannerToggle(
												active: scannerActive,
												connected: scannerConnected,
												onChanged: onScannerToggle,
											),
										],
									],
								),
								if (scannerActive)
									Padding(
										padding: const EdgeInsets.only(top: 6.0),
										child: Text(
											'Physical scanner active – scan a code',
											style: Theme.of(context).textTheme.labelSmall?.copyWith(
												color: Theme.of(context).colorScheme.primary,
											),
										),
							],
						),
					),
				),
		);
	}
}
																								child: ConstrainedBox(
																									constraints: const BoxConstraints(maxWidth: 520),
																									child: Column(
																										crossAxisAlignment: CrossAxisAlignment.start,
																										children: [
																											// Customer search field (optional) with trailing icons + scanner
																											if (customerSearchController != null) ...[
																												Row(
																													children: [
																														Expanded(
																															child: TextField(
																																controller: customerSearchController,
																																decoration: const InputDecoration(
																																	labelText: 'Search customer',
																																	prefixIcon: Icon(Icons.person_search_outlined),
																																),
																																onChanged: (_) => onCustomerQueryChanged?.call(),
																															),
																														),
																														if (customerSelector != null) ...[
																															const SizedBox(width: 8),
																															Flexible(flex: 0, child: customerSelector!),
																														],
																														const SizedBox(width: 8),
																														_ScannerToggle(
																															active: scannerActive,
																															connected: scannerConnected,
																															onChanged: onScannerToggle,
																														),
																													],
																												),
																												// Inline suggestions list (shows only when user is actively searching)
																												if ((customerSuggestions ?? const <Customer>[]).isNotEmpty &&
																														((customerSearchController?.text.trim() ?? '').isNotEmpty) &&
																														((customerSearchController?.text.trim() ?? '').length >= 2) &&
																														((customerSearchController?.text.trim() ?? '') != (selectedCustomerName ?? '').trim()))
																													Container(
																														margin: const EdgeInsets.only(top: 6.0, bottom: 6.0),
																														constraints: const BoxConstraints(maxHeight: 180),
																														decoration: BoxDecoration(
																															border: Border.all(color: Theme.of(context).dividerColor),
																															borderRadius: BorderRadius.circular(8),
																															color: Theme.of(context).colorScheme.surface,
																														),
																														child: ListView.builder(
																															itemCount: customerSuggestions!.length,
																															itemBuilder: (_, i) {
																																final c = customerSuggestions![i];
																																return ListTile(
																																	leading: const Icon(Icons.person_outline),
																																	dense: true,
																																	title: Text(c.name, overflow: TextOverflow.ellipsis),
																																	onTap: () {
																																	// Fill the field with selected customer's name and notify parent
																																	customerSearchController!.text = c.name;
																																	onCustomerSelected?.call(c);
																																	// Hide keyboard and suggestion list
																																	FocusScope.of(context).unfocus();
																																},
																															);
																														},
																													),
																												),
																											],
																											Row(
																												children: [
																													// Move actions (All/Favorite) to the left side
																													if (barcodeTrailing != null) ...[
																														Flexible(flex: 0, child: barcodeTrailing!),
																														const SizedBox(width: 8),
																													],
																													Expanded(
																														child: TextField(
																															controller: searchController,
																															decoration: const InputDecoration(
																																labelText: 'Barcode / SKU or Search',
																																prefixIcon: Icon(Icons.qr_code_scanner),
																															),
																															onSubmitted: (_) => onBarcodeSubmitted(),
																															onChanged: (_) => onSearchChanged(),
																														),
																													),
																													// If there's a customer row above, keep barcode row clean
																													if (customerSearchController == null && customerSelector != null) ...[
																														const SizedBox(width: 8),
																														Flexible(flex: 0, child: customerSelector!),
																													],
																													if (customerSearchController == null) ...[
																														const SizedBox(width: 8),
																														_ScannerToggle(
																															active: scannerActive,
																															connected: scannerConnected,
																															onChanged: onScannerToggle,
																														),
																													],
																												],
																											),
																											if (scannerActive)
																												Padding(
																													padding: const EdgeInsets.only(top: 6.0),
																													child: Text(
																														'Physical scanner active – scan a code',
																														style: Theme.of(context).textTheme.labelSmall?.copyWith(
																															color: Theme.of(context).colorScheme.primary,
																														),
																													),
																											],
																										),
																									),
																								),
																						),
																					);
																				}
																			}
		required this.allProducts,
		required this.favoriteSkus,
		required this.onAdd,
	});

	@override
	Widget build(BuildContext context) {
		final popular = allProducts.where((p) => favoriteSkus.contains(p.sku)).toList();
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(8.0),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
										Text(
											'Popular Items',
											style: Theme.of(context)
													.textTheme
													.titleSmall
													?.copyWith(fontWeight: FontWeight.bold),
										),
					const SizedBox(height: 8),
					if (popular.isEmpty) ...[
						const Padding(
							padding: EdgeInsets.all(8.0),
							child: Text('Mark items as favorite to see them here.'),
						),
					] else ...[
						GridView.builder(
							shrinkWrap: true,
							physics: const NeverScrollableScrollPhysics(),
							itemCount: popular.length,
							gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 3),
							itemBuilder: (_, i) {
								final p = popular[i];
								return ElevatedButton(
									onPressed: () => onAdd(p),
									child: Text('${p.name} • ₹${p.price.toStringAsFixed(2)}', overflow: TextOverflow.ellipsis),
								);
							},
						),
					],
				]),
			),
		);
	}
}

*/
import 'package:flutter/material.dart';

import 'pos.dart';

// Clean, compilable replacement below
class PosSearchAndScanCard extends StatelessWidget {
	final TextEditingController barcodeController;
	final TextEditingController searchController;
	final TextEditingController? customerSearchController;
	final List<Customer>? customerSuggestions;
	final ValueChanged<Customer>? onCustomerSelected;
	final VoidCallback? onCustomerQueryChanged;
	final String? selectedCustomerName;
	final bool scannerActive;
	final bool scannerConnected;
	final ValueChanged<bool> onScannerToggle;
	final VoidCallback onBarcodeSubmitted;
	final VoidCallback onSearchChanged;
	final Widget? customerSelector;
	final Widget? barcodeTrailing;

	const PosSearchAndScanCard({
		super.key,
		required this.barcodeController,
		required this.searchController,
		this.customerSearchController,
		this.customerSuggestions,
		this.onCustomerSelected,
		this.onCustomerQueryChanged,
		this.selectedCustomerName,
		required this.scannerActive,
		required this.scannerConnected,
		required this.onScannerToggle,
		required this.onBarcodeSubmitted,
		required this.onSearchChanged,
		this.customerSelector,
		this.barcodeTrailing,
	});

	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12.0),
				child: Align(
					alignment: Alignment.centerLeft,
					child: ConstrainedBox(
						constraints: const BoxConstraints(maxWidth: 520),
						child: Column(
							crossAxisAlignment: CrossAxisAlignment.start,
							mainAxisSize: MainAxisSize.min,
							children: [
								if (customerSearchController != null) ...[
									Row(
										children: [
											Expanded(
												child: TextField(
													controller: customerSearchController,
													decoration: const InputDecoration(
														labelText: 'Search customer',
														prefixIcon: Icon(Icons.person_search_outlined),
													),
													onChanged: (_) => onCustomerQueryChanged?.call(),
												),
											),
											if (customerSelector != null) ...[
												const SizedBox(width: 8),
												Flexible(flex: 0, child: customerSelector!),
											],
											const SizedBox(width: 8),
											_ScannerToggle(
												active: scannerActive,
												connected: scannerConnected,
												onChanged: onScannerToggle,
											),
										],
									),
									if ((customerSuggestions ?? const <Customer>[]).isNotEmpty &&
											((customerSearchController?.text.trim() ?? '').isNotEmpty) &&
											((customerSearchController?.text.trim() ?? '').length >= 2) &&
											((customerSearchController?.text.trim() ?? '') != (selectedCustomerName ?? '').trim()))
										Container(
											margin: const EdgeInsets.only(top: 6.0, bottom: 6.0),
											constraints: const BoxConstraints(maxHeight: 180),
											decoration: BoxDecoration(
												border: Border.all(color: Theme.of(context).dividerColor),
												borderRadius: BorderRadius.circular(8),
												color: Theme.of(context).colorScheme.surface,
											),
											child: ListView.builder(
												itemCount: customerSuggestions!.length,
												itemBuilder: (_, i) {
													final c = customerSuggestions![i];
													return ListTile(
														leading: const Icon(Icons.person_outline),
														dense: true,
														title: Text(c.name, overflow: TextOverflow.ellipsis),
														onTap: () {
															customerSearchController!.text = c.name;
															onCustomerSelected?.call(c);
															FocusScope.of(context).unfocus();
														},
													);
												},
											),
										),
								],
								Row(
									children: [
										if (barcodeTrailing != null) ...[
											Flexible(flex: 0, child: barcodeTrailing!),
											const SizedBox(width: 8),
										],
										Expanded(
											child: TextField(
												controller: searchController,
												decoration: const InputDecoration(
													labelText: 'Barcode / SKU or Search',
													prefixIcon: Icon(Icons.qr_code_scanner),
												),
												onSubmitted: (_) => onBarcodeSubmitted(),
												onChanged: (_) => onSearchChanged(),
											),
										),
										if (customerSearchController == null && customerSelector != null) ...[
											const SizedBox(width: 8),
											Flexible(flex: 0, child: customerSelector!),
										],
										if (customerSearchController == null) ...[
											const SizedBox(width: 8),
											_ScannerToggle(
												active: scannerActive,
												connected: scannerConnected,
												onChanged: onScannerToggle,
											),
										],
									],
								),
								if (scannerActive)
									Padding(
										padding: const EdgeInsets.only(top: 6.0),
										child: Text(
											'Physical scanner active – scan a code',
											style: Theme.of(context).textTheme.labelSmall?.copyWith(
														color: Theme.of(context).colorScheme.primary,
													),
										),
									),
							],
						),
					),
				),
			),
		);
	}
}

class PosProductGrid extends StatelessWidget {
	final List<Product> products;
	final Set<String> favoriteSkus;
	final ValueChanged<Product> onAdd;
	final ValueChanged<Product> onToggleFavorite;

	const PosProductGrid({
		super.key,
		required this.products,
		required this.favoriteSkus,
		required this.onAdd,
		required this.onToggleFavorite,
	});

	@override
	Widget build(BuildContext context) {
		final width = MediaQuery.of(context).size.width;
		final cols = (width ~/ 160).clamp(2, 4);
		return Card(
			child: GridView.builder(
				padding: const EdgeInsets.all(8),
				gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
					crossAxisCount: cols,
					crossAxisSpacing: 8,
					mainAxisSpacing: 8,
					childAspectRatio: 1.0,
				),
				itemCount: products.length,
				itemBuilder: (_, i) {
					final p = products[i];
					final isFav = favoriteSkus.contains(p.sku);
					return InkWell(
						onTap: () => onAdd(p),
						child: Container(
							decoration: BoxDecoration(
								borderRadius: BorderRadius.circular(8),
								border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
							),
							padding: const EdgeInsets.all(8),
							child: Column(
								crossAxisAlignment: CrossAxisAlignment.start,
								children: [
									Text(
										p.name,
										maxLines: 2,
										overflow: TextOverflow.ellipsis,
										style: Theme.of(context).textTheme.bodyMedium,
									),
									const Spacer(),
									Row(
										mainAxisAlignment: MainAxisAlignment.spaceBetween,
										children: [
											Flexible(
												child: Text(
													'₹${p.price.toStringAsFixed(2)}',
													style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
													overflow: TextOverflow.ellipsis,
												),
											),
											IconButton(
												tooltip: isFav ? 'Unfavorite' : 'Mark favorite',
												icon: Icon(
													isFav ? Icons.star : Icons.star_border,
													color: isFav ? Theme.of(context).colorScheme.tertiary : null,
												),
												onPressed: () => onToggleFavorite(p),
												visualDensity: VisualDensity.compact,
												padding: EdgeInsets.zero,
												constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
											),
										],
									),
								],
							),
						),
					);
				},
			),
		);
	}
}

class PosPopularItemsGrid extends StatelessWidget {
	final List<Product> allProducts;
	final Set<String> favoriteSkus;
	final ValueChanged<Product> onAdd;

	const PosPopularItemsGrid({
		super.key,
		required this.allProducts,
		required this.favoriteSkus,
		required this.onAdd,
	});

	@override
	Widget build(BuildContext context) {
		final popular = allProducts.where((p) => favoriteSkus.contains(p.sku)).toList();
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(8.0),
				child: Column(
					crossAxisAlignment: CrossAxisAlignment.start,
					children: [
						Text(
							'Popular Items',
							style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
						),
						const SizedBox(height: 8),
						if (popular.isEmpty) ...[
							const Padding(
								padding: EdgeInsets.all(8.0),
								child: Text('Mark items as favorite to see them here.'),
							),
						] else ...[
							GridView.builder(
								shrinkWrap: true,
								physics: const NeverScrollableScrollPhysics(),
								itemCount: popular.length,
								gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
									crossAxisCount: 3,
									crossAxisSpacing: 8,
									mainAxisSpacing: 8,
									childAspectRatio: 3,
								),
								itemBuilder: (_, i) {
									final p = popular[i];
									return ElevatedButton(
										onPressed: () => onAdd(p),
										child: Text('${p.name} • ₹${p.price.toStringAsFixed(2)}', overflow: TextOverflow.ellipsis),
									);
								},
							),
						],
					],
				),
			),
		);
	}
}

class _ScannerToggle extends StatelessWidget {
	final bool active;
	final bool connected;
	final ValueChanged<bool> onChanged;
	const _ScannerToggle({required this.active, required this.connected, required this.onChanged});

	Color _statusColor(BuildContext context) {
		final scheme = Theme.of(context).colorScheme;
		if (!active) return scheme.outline;
		return connected ? scheme.primary : scheme.error;
	}

	@override
	Widget build(BuildContext context) {
		return Column(
			mainAxisSize: MainAxisSize.min,
			children: [
				Row(
					mainAxisSize: MainAxisSize.min,
					children: [
						Switch(
							value: active,
							onChanged: (v) => onChanged(v),
						),
						const SizedBox(width: 4),
						Container(
							width: 14,
							height: 14,
							decoration: BoxDecoration(
								shape: BoxShape.circle,
								color: _statusColor(context),
								border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
							),
						),
					],
				),
				Text('Scanner', style: Theme.of(context).textTheme.labelSmall),
			],
		);
	}
}

class CartSection extends StatelessWidget {
	final Map<String, CartItem> cart;
	final List<HeldOrder> heldOrders;
	final VoidCallback onHold;
	final Future<HeldOrder?> Function(BuildContext) onResumeSelect;
	final VoidCallback onClear;
	final void Function(String sku, int delta) onChangeQty;
	final void Function(String sku) onRemove;

	const CartSection({
		super.key,
		required this.cart,
		required this.heldOrders,
		required this.onHold,
		required this.onResumeSelect,
		required this.onClear,
		required this.onChangeQty,
		required this.onRemove,
	});

	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(8.0),
				child: Column(
					crossAxisAlignment: CrossAxisAlignment.start,
					children: [
						Row(
							crossAxisAlignment: CrossAxisAlignment.center,
							children: [
								Text(
									'Cart',
									style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
								),
								const SizedBox(width: 8),
								Expanded(
									child: Align(
										alignment: Alignment.centerRight,
										child: SingleChildScrollView(
											scrollDirection: Axis.horizontal,
											child: Row(
												mainAxisSize: MainAxisSize.min,
												children: [
													ElevatedButton.icon(
														onPressed: onHold,
														icon: const Icon(Icons.pause_circle),
														label: const Text('Hold'),
													),
													const SizedBox(width: 8),
													ElevatedButton.icon(
														onPressed: heldOrders.isEmpty
																? null
																: () async {
																		final sel = await onResumeSelect(context);
																		if (sel != null) {
																			// Parent handles resume using the returned held order
																		}
																	},
														icon: const Icon(Icons.play_circle),
														label: const Text('Resume'),
													),
													const SizedBox(width: 8),
													ElevatedButton.icon(
														onPressed: cart.isEmpty ? null : onClear,
														icon: const Icon(Icons.delete_sweep),
														label: const Text('Clear'),
													),
												],
											),
										),
									),
								),
							],
						),
						const SizedBox(height: 6),
						Expanded(
							child: cart.isEmpty
									? const Center(child: Text('Cart is empty'))
									: ListView.separated(
											itemCount: cart.length,
											separatorBuilder: (_, __) => const Divider(height: 1),
											itemBuilder: (_, i) {
												final item = cart.values.elementAt(i);
												final line = item.product.price * item.qty;
												return ListTile(
													title: Text(
														item.product.name,
														maxLines: 1,
														overflow: TextOverflow.ellipsis,
													),
													subtitle: null,
													leading: null,
													trailing: ConstrainedBox(
														constraints: const BoxConstraints(maxWidth: 180),
														child: Row(
															mainAxisAlignment: MainAxisAlignment.end,
															crossAxisAlignment: CrossAxisAlignment.center,
															children: [
																IconButton(
																	icon: const Icon(Icons.remove),
																	onPressed: () => onChangeQty(item.product.sku, -1),
																	padding: EdgeInsets.zero,
																	visualDensity: VisualDensity.compact,
																	constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
																),
																const SizedBox(width: 2),
																Text(item.qty.toString()),
																const SizedBox(width: 2),
																IconButton(
																	icon: const Icon(Icons.add),
																	onPressed: () => onChangeQty(item.product.sku, 1),
																	padding: EdgeInsets.zero,
																	visualDensity: VisualDensity.compact,
																	constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
																),
																const SizedBox(width: 4),
																Flexible(
																	child: Text(
																		'₹${line.toStringAsFixed(2)}',
																		overflow: TextOverflow.ellipsis,
																		softWrap: false,
																	),
																),
																const SizedBox(width: 4),
																IconButton(
																	icon: const Icon(Icons.close),
																	onPressed: () => onRemove(item.product.sku),
																	padding: EdgeInsets.zero,
																	visualDensity: VisualDensity.compact,
																	constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
																),
															],
														),
													),
												);
											},
										),
						),
					],
				),
			),
		);
	}
}

class CartHoldController {
	final Map<String, CartItem> cart;
	final List<HeldOrder> heldOrders;
	DiscountType discountType;
	final TextEditingController discountCtrl;
	final void Function() notify; // typically setState
	final void Function(String message) showMessage;

	CartHoldController({
		required this.cart,
		required this.heldOrders,
		required this.discountType,
		required this.discountCtrl,
		required this.notify,
		required this.showMessage,
	});

	void holdCart() {
		if (cart.isEmpty) return showMessage('Cart is empty');
		final snapshot = HeldOrder(
			id: 'HLD-${heldOrders.length + 1}',
			timestamp: DateTime.now(),
			items: cart.values.map((e) => e.copy()).toList(),
			discountType: discountType,
			discountValueText: discountCtrl.text,
		);
		heldOrders.add(snapshot);
		cart.clear();
		notify();
		showMessage('Order ${snapshot.id} held');
	}

	void resumeHeld(HeldOrder order) {
		cart.clear();
		for (final it in order.items) {
			cart[it.product.sku] = it.copy();
		}
		discountType = order.discountType;
		discountCtrl.text = order.discountValueText;
		heldOrders.removeWhere((o) => o.id == order.id);
		notify();
	}
}
class _ScannerToggle extends StatelessWidget {
	final bool active;
	final bool connected;
	final ValueChanged<bool> onChanged;
	const _ScannerToggle({required this.active, required this.connected, required this.onChanged});

	Color _statusColor(BuildContext context) {
		final scheme = Theme.of(context).colorScheme;
		if (!active) return scheme.outline;
		return connected ? scheme.primary : scheme.error;
	}

	@override
	Widget build(BuildContext context) {
		return Column(
			mainAxisSize: MainAxisSize.min,
			children: [
				Row(
					mainAxisSize: MainAxisSize.min,
					children: [
						Switch(
							value: active,
							onChanged: (v) => onChanged(v),
						),
						const SizedBox(width: 4),
						Container(
							width: 14,
							height: 14,
							decoration: BoxDecoration(
								shape: BoxShape.circle,
								color: _statusColor(context),
								border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
							),
						),
					],
				),
				Text('Scanner', style: Theme.of(context).textTheme.labelSmall),
			],
		);
	}
}

class CartSection extends StatelessWidget {
	final Map<String, CartItem> cart;
	final List<HeldOrder> heldOrders;
	final VoidCallback onHold;
	final Future<HeldOrder?> Function(BuildContext) onResumeSelect;
	final VoidCallback onClear;
	final void Function(String sku, int delta) onChangeQty;
	final void Function(String sku) onRemove;

	const CartSection({
		super.key,
		required this.cart,
		required this.heldOrders,
		required this.onHold,
		required this.onResumeSelect,
		required this.onClear,
		required this.onChangeQty,
		required this.onRemove,
	});

	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(8.0),
					child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
						// Cart header: keep actions in a single horizontal row with scroll when tight
						Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
							Text(
								'Cart',
								style: Theme.of(context)
										.textTheme
										.titleMedium
										?.copyWith(fontWeight: FontWeight.bold),
							),
							const SizedBox(width: 8),
							Expanded(
								child: Align(
									alignment: Alignment.centerRight,
									child: SingleChildScrollView(
										scrollDirection: Axis.horizontal,
										child: Row(
											mainAxisSize: MainAxisSize.min,
											children: [
												ElevatedButton.icon(onPressed: onHold, icon: const Icon(Icons.pause_circle), label: const Text('Hold')),
												const SizedBox(width: 8),
												ElevatedButton.icon(
													onPressed: heldOrders.isEmpty
														? null
														: () async {
															final sel = await onResumeSelect(context);
															if (sel != null) {
																// parent will handle resume; we just trigger by returning object
															}
														},
													icon: const Icon(Icons.play_circle),
													label: const Text('Resume'),
												),
												const SizedBox(width: 8),
												ElevatedButton.icon(
													onPressed: cart.isEmpty ? null : onClear,
													icon: const Icon(Icons.delete_sweep),
													label: const Text('Clear'),
												),
											],
										),
									),
								),
							),
						]),
					const SizedBox(height: 6),
					Expanded(
						child: cart.isEmpty
								? const Center(child: Text('Cart is empty'))
								: ListView.separated(
										itemCount: cart.length,
										separatorBuilder: (_, __) => const Divider(height: 1),
										itemBuilder: (_, i) {
											final item = cart.values.elementAt(i);
											final line = item.product.price * item.qty;
												return ListTile(
													title: Text(
														item.product.name,
														maxLines: 1,
														overflow: TextOverflow.ellipsis,
													),
											// Hide duplicate unit price and GST% under the product title in cart items
											subtitle: null,
											// Remove the leading minus-in-circle icon per request
											leading: null,
												trailing: ConstrainedBox(
													constraints: const BoxConstraints(maxWidth: 180),
													child: Row(
														mainAxisAlignment: MainAxisAlignment.end,
														crossAxisAlignment: CrossAxisAlignment.center,
														children: [
															IconButton(
																icon: const Icon(Icons.remove),
																onPressed: () => onChangeQty(item.product.sku, -1),
																padding: EdgeInsets.zero,
																visualDensity: VisualDensity.compact,
																constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
															),
															const SizedBox(width: 2),
															Text(item.qty.toString()),
															const SizedBox(width: 2),
															IconButton(
																icon: const Icon(Icons.add),
																onPressed: () => onChangeQty(item.product.sku, 1),
																padding: EdgeInsets.zero,
																visualDensity: VisualDensity.compact,
																constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
															),
															const SizedBox(width: 4),
															Flexible(
																child: Text(
																	'₹${line.toStringAsFixed(2)}',
																	overflow: TextOverflow.ellipsis,
																	softWrap: false,
																),
															),
															const SizedBox(width: 4),
															IconButton(
																icon: const Icon(Icons.close),
																onPressed: () => onRemove(item.product.sku),
																padding: EdgeInsets.zero,
																visualDensity: VisualDensity.compact,
																constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
															),
														],
													),
												),
											);
										},
									),
					),
				]),
			),
		);
	}
}

class CartHoldController {
	final Map<String, CartItem> cart;
	final List<HeldOrder> heldOrders;
	DiscountType discountType;
	final TextEditingController discountCtrl;
	final void Function() notify; // typically setState
	final void Function(String message) showMessage;

	CartHoldController({
		required this.cart,
		required this.heldOrders,
		required this.discountType,
		required this.discountCtrl,
		required this.notify,
		required this.showMessage,
	});

	void holdCart() {
		if (cart.isEmpty) return showMessage('Cart is empty');
		final snapshot = HeldOrder(
			id: 'HLD-${heldOrders.length + 1}',
			timestamp: DateTime.now(),
			items: cart.values.map((e) => e.copy()).toList(),
			discountType: discountType,
			discountValueText: discountCtrl.text,
		);
		heldOrders.add(snapshot);
		cart.clear();
		notify();
		showMessage('Order ${snapshot.id} held');
	}

	void resumeHeld(HeldOrder order) {
		cart.clear();
		for (final it in order.items) {
			cart[it.product.sku] = it.copy();
		}
		discountType = order.discountType;
		discountCtrl.text = order.discountValueText;
		heldOrders.removeWhere((o) => o.id == order.id);
		notify();
	}
}
*/
export 'pos_search_scan_fav_fixed.dart';
