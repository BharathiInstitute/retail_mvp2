import 'package:flutter/material.dart';

import 'pos.dart';

// Search + barcode + scanner toggle card
class PosSearchAndScanCard extends StatelessWidget {
	final TextEditingController barcodeController;
	final TextEditingController searchController;
	final bool scannerActive;
	final bool scannerConnected;
	final ValueChanged<bool> onScannerToggle;
	final VoidCallback onBarcodeSubmitted;
	final VoidCallback onSearchChanged;

	const PosSearchAndScanCard({
		super.key,
		required this.barcodeController,
		required this.searchController,
		required this.scannerActive,
		required this.scannerConnected,
		required this.onScannerToggle,
		required this.onBarcodeSubmitted,
		required this.onSearchChanged,
	});

	@override
	Widget build(BuildContext context) {
		return Card(
			child: Padding(
				padding: const EdgeInsets.all(12.0),
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					Row(children: [
						Expanded(
							child: TextField(
								controller: barcodeController,
								decoration: const InputDecoration(
									labelText: 'Barcode / SKU',
									prefixIcon: Icon(Icons.qr_code_scanner),
								),
								onSubmitted: (_) => onBarcodeSubmitted(),
							),
						),
						const SizedBox(width: 8),
						_ScannerToggle(
							active: scannerActive,
							connected: scannerConnected,
							onChanged: onScannerToggle,
						),
					]),
					const SizedBox(height: 8),
					TextField(
						controller: searchController,
						decoration: const InputDecoration(
							labelText: 'Quick Product Search',
							prefixIcon: Icon(Icons.search),
						),
						onChanged: (_) => onSearchChanged(),
					),
					if (scannerActive)
						Padding(
							padding: const EdgeInsets.only(top: 6.0),
							child: Text('Physical scanner active – scan a code', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12)),
						),
				]),
			),
		);
	}
}

class PosProductList extends StatelessWidget {
	final List<Product> products;
	final Set<String> favoriteSkus;
	final ValueChanged<Product> onAdd;
	final ValueChanged<Product> onToggleFavorite;

	const PosProductList({
		super.key,
		required this.products,
		required this.favoriteSkus,
		required this.onAdd,
		required this.onToggleFavorite,
	});

	@override
	Widget build(BuildContext context) {
		return Card(
			child: ListView.separated(
				itemCount: products.length,
				separatorBuilder: (_, __) => const Divider(height: 1),
				itemBuilder: (_, i) {
					final p = products[i];
						final isFav = favoriteSkus.contains(p.sku);
						return ListTile(
							title: Text('${p.name}  •  ₹${p.price.toStringAsFixed(2)}'),
							subtitle: Text('SKU: ${p.sku}  •  Stock: ${p.stock}  •  GST ${p.taxPercent}%'),
							trailing: IconButton(
								tooltip: isFav ? 'Unfavorite' : 'Mark favorite',
								icon: Icon(isFav ? Icons.star : Icons.star_border, color: isFav ? Colors.amber : null),
								onPressed: () => onToggleFavorite(p),
							),
							onTap: () => onAdd(p),
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
				child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
					const Text('Popular Items', style: TextStyle(fontWeight: FontWeight.bold)),
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

class _ScannerToggle extends StatelessWidget {
	final bool active;
	final bool connected;
	final ValueChanged<bool> onChanged;
	const _ScannerToggle({required this.active, required this.connected, required this.onChanged});

	Color _statusColor(BuildContext context) {
		if (!active) return Theme.of(context).colorScheme.outline;
		return connected ? Colors.green : Colors.red;
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
					Row(
						children: [
							const Text('Cart', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
							const Spacer(),
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
												title: Text(item.product.name),
												subtitle: Text('₹${item.product.price.toStringAsFixed(2)}  •  GST ${item.product.taxPercent}%'),
												leading: IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () => onChangeQty(item.product.sku, -1)),
												trailing: SizedBox(
													width: 190,
													child: Row(
														mainAxisAlignment: MainAxisAlignment.end,
														children: [
															IconButton(icon: const Icon(Icons.remove), onPressed: () => onChangeQty(item.product.sku, -1)),
															Text(item.qty.toString()),
															IconButton(icon: const Icon(Icons.add), onPressed: () => onChangeQty(item.product.sku, 1)),
															const SizedBox(width: 6),
															Text('₹${line.toStringAsFixed(2)}'),
															IconButton(icon: const Icon(Icons.close), onPressed: () => onRemove(item.product.sku)),
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
