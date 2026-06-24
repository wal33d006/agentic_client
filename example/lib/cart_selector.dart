import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

/// Step 1 of the two-step cart flow.
///
/// Renders a checklist of items bound to `/items` in the surface data model
/// (a list of `{id, name, price, selected}`) plus a running total bound to
/// `/total`. Tapping a row fires a `toggleCartItem` action carrying the item
/// id; the backend flips `selected` in shared state and patches the data
/// model so the checkbox + total refresh. "Proceed to Checkout" fires
/// `cartCheckout`, which renders step 2 (`CartSummary`) from the same
/// shared state.
final _cartSelectorSchema = S.object(
  description:
      'Step 1 of a cart flow: a checklist of items with a running total and a '
      'Proceed-to-Checkout button. `items` is a list of '
      '{id, name, price, selected}.',
  properties: {
    'items': A2uiSchemas.listOrReference(
      items: S.object(
        properties: {
          'id': S.string(),
          'name': S.string(),
          'price': S.number(),
          'selected': S.boolean(),
        },
      ),
    ),
    'total': A2uiSchemas.stringReference(),
  },
  required: ['items'],
);

final cartSelectorItem = CatalogItem(
  name: 'CartSelector',
  dataSchema: _cartSelectorSchema,
  widgetBuilder: (ctx) {
    final data = ctx.data as Map<String, Object?>;
    return BoundList(
      dataContext: ctx.dataContext,
      value: data['items'],
      builder: (context, items) {
        return BoundString(
          dataContext: ctx.dataContext,
          value: data['total'],
          builder: (context, total) => _CartSelectorView(
            items: _coerceItems(items),
            total: total ?? r'$0.00',
            onToggle: (id) => ctx.dispatchEvent(
              UserActionEvent(
                name: 'toggleCartItem',
                sourceComponentId: ctx.id,
                context: {'item_id': id},
              ),
            ),
            onCheckout: () => ctx.dispatchEvent(
              UserActionEvent(name: 'cartCheckout', sourceComponentId: ctx.id),
            ),
          ),
        );
      },
    );
  },
);

/// Normalises the loosely-typed data-model list into typed cart rows.
List<CartItem> _coerceItems(List<Object?>? raw) {
  if (raw == null) return const [];
  return raw.whereType<Map>().map((m) {
    final map = m.cast<String, Object?>();
    return CartItem(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      price: (map['price'] as num?)?.toDouble() ?? 0,
      selected: map['selected'] == true,
    );
  }).toList();
}

/// A single purchasable row shared across the cart and food-ordering flows.
class CartItem {
  const CartItem({
    required this.id,
    required this.name,
    required this.price,
    this.selected = false,
    this.qty = 1,
  });

  final String id;
  final String name;
  final double price;
  final bool selected;
  final int qty;

  /// Unit price, e.g. "$9.99".
  String get priceLabel => '\$${price.toStringAsFixed(2)}';

  /// Line total (price × qty), e.g. "$19.98".
  String get lineTotalLabel => '\$${(price * qty).toStringAsFixed(2)}';
}

class _CartSelectorView extends StatelessWidget {
  const _CartSelectorView({
    required this.items,
    required this.total,
    required this.onToggle,
    required this.onCheckout,
  });

  final List<CartItem> items;
  final String total;
  final void Function(String id) onToggle;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selectedCount = items.where((i) => i.selected).length;

    return Container(
      constraints: const BoxConstraints(maxWidth: 360),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.shopping_cart_outlined, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text('Select items', style: theme.textTheme.titleMedium),
                const Spacer(),
                Text('Step 1 of 2', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          for (final item in items)
            InkWell(
              onTap: () => onToggle(item.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Checkbox(
                      value: item.selected,
                      onChanged: (_) => onToggle(item.id),
                    ),
                    Expanded(
                      child: Text(item.name, style: theme.textTheme.bodyLarge),
                    ),
                    Text(item.priceLabel, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Text('Total', style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Text(
                  total,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: selectedCount == 0 ? null : onCheckout,
                  child: Text(selectedCount == 0 ? 'Select items' : 'Proceed to Checkout'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
