import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'food_theme.dart';

/// Step 2 of the food-ordering flow.
///
/// Renders the selected restaurant's menu bound to `/items` (a list of
/// `{id, name, price, qty}`, where `qty` is the amount currently in the
/// cart). Each row shows an "Add" button, or a − qty + stepper once the item
/// is in the cart; both fire `addToCart` / `removeFromCart` with the item id.
/// The footer shows the live cart count + total (bound to `/cartCount` and
/// `/cartTotal`) and a "View Cart" button that fires `viewCheckout`. The
/// header back button fires `listRestaurants` to return to step 1.
final _restaurantMenuSchema = S.object(
  description:
      'Step 2 of the food-ordering flow: a restaurant menu. `items` is a list '
      'of {id, name, price, qty} (qty = amount in cart); `cartCount` and '
      '`cartTotal` summarise the cart.',
  properties: {
    'restaurantName': A2uiSchemas.stringReference(),
    'items': A2uiSchemas.listOrReference(
      items: S.object(
        properties: {
          'id': S.string(),
          'name': S.string(),
          'price': S.number(),
          'qty': S.integer(),
        },
      ),
    ),
    'cartCount': A2uiSchemas.stringReference(),
    'cartTotal': A2uiSchemas.stringReference(),
  },
  required: ['items'],
);

final restaurantMenuItem = CatalogItem(
  name: 'RestaurantMenu',
  dataSchema: _restaurantMenuSchema,
  widgetBuilder: (ctx) {
    final data = ctx.data as Map<String, Object?>;
    return BoundString(
      dataContext: ctx.dataContext,
      value: data['restaurantName'],
      builder: (context, restaurantName) {
        return BoundList(
          dataContext: ctx.dataContext,
          value: data['items'],
          builder: (context, items) {
            return BoundString(
              dataContext: ctx.dataContext,
              value: data['cartCount'],
              builder: (context, cartCount) {
                return BoundString(
                  dataContext: ctx.dataContext,
                  value: data['cartTotal'],
                  builder: (context, cartTotal) => _RestaurantMenuView(
                    restaurantName: restaurantName ?? 'Menu',
                    items: _coerceItems(items),
                    cartCount: int.tryParse(cartCount ?? '0') ?? 0,
                    cartTotal: cartTotal ?? r'$0.00',
                    onAdd: (id) => ctx.dispatchEvent(
                      UserActionEvent(
                        name: 'addToCart',
                        sourceComponentId: ctx.id,
                        context: {'item_id': id},
                      ),
                    ),
                    onRemove: (id) => ctx.dispatchEvent(
                      UserActionEvent(
                        name: 'removeFromCart',
                        sourceComponentId: ctx.id,
                        context: {'item_id': id},
                      ),
                    ),
                    onBack: () => ctx.dispatchEvent(
                      UserActionEvent(name: 'listRestaurants', sourceComponentId: ctx.id),
                    ),
                    onCheckout: () => ctx.dispatchEvent(
                      UserActionEvent(name: 'viewCheckout', sourceComponentId: ctx.id),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  },
);

class MenuItem {
  const MenuItem({
    required this.id,
    required this.name,
    required this.price,
    required this.qty,
  });

  final String id;
  final String name;
  final double price;
  final int qty;

  String get priceLabel => '\$${price.toStringAsFixed(2)}';
}

List<MenuItem> _coerceItems(List<Object?>? raw) {
  if (raw == null) return const [];
  return raw.whereType<Map>().map((m) {
    final map = m.cast<String, Object?>();
    return MenuItem(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      price: (map['price'] as num?)?.toDouble() ?? 0,
      qty: (map['qty'] as num?)?.toInt() ?? 0,
    );
  }).toList();
}

class _RestaurantMenuView extends StatelessWidget {
  const _RestaurantMenuView({
    required this.restaurantName,
    required this.items,
    required this.cartCount,
    required this.cartTotal,
    required this.onAdd,
    required this.onRemove,
    required this.onBack,
    required this.onCheckout,
  });

  final String restaurantName;
  final List<MenuItem> items;
  final int cartCount;
  final String cartTotal;
  final void Function(String id) onAdd;
  final void Function(String id) onRemove;
  final VoidCallback onBack;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return FoodCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FoodHeader(
            emoji: cuisineEmoji(restaurantName),
            title: restaurantName,
            subtitle: 'Add dishes to your cart',
            step: '2 of 3',
            onBack: onBack,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16, color: FoodTheme.hairline),
                  _MenuRow(
                    item: items[i],
                    onAdd: () => onAdd(items[i].id),
                    onRemove: () => onRemove(items[i].id),
                  ),
                ],
              ],
            ),
          ),
          // Sticky-looking cart bar.
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFFF7F2),
              border: Border(top: BorderSide(color: FoodTheme.hairline)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$cartCount item${cartCount == 1 ? '' : 's'}',
                      style: textTheme.labelSmall?.copyWith(color: FoodTheme.inkSoft),
                    ),
                    Text(
                      cartTotal,
                      style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, color: FoodTheme.brandDeep),
                    ),
                  ],
                ),
                const Spacer(),
                GradientButton(
                  label: 'View Cart',
                  icon: Icons.shopping_bag_rounded,
                  onPressed: cartCount == 0 ? null : onCheckout,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.item, required this.onAdd, required this.onRemove});

  final MenuItem item;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          EmojiAvatar(emoji: foodEmoji(item.name)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600, color: FoodTheme.ink),
                ),
                const SizedBox(height: 2),
                Text(
                  item.priceLabel,
                  style: textTheme.bodyMedium?.copyWith(color: FoodTheme.brandDeep, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _QtyControl(item: item, onAdd: onAdd, onRemove: onRemove),
        ],
      ),
    );
  }
}

/// "Add" button when the item isn't in the cart, or a − qty + stepper once it
/// is.
class _QtyControl extends StatelessWidget {
  const _QtyControl({required this.item, required this.onAdd, required this.onRemove});

  final MenuItem item;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (item.qty <= 0) {
      return Material(
        color: FoodTheme.avatarBg,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onAdd,
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add_rounded, size: 16, color: FoodTheme.brandDeep),
                SizedBox(width: 4),
                Text('Add', style: TextStyle(color: FoodTheme.brandDeep, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: FoodTheme.appetiteGradient),
        borderRadius: BorderRadius.circular(24),
        boxShadow: const [BoxShadow(color: FoodTheme.brandShadow, blurRadius: 10, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RoundIcon(icon: Icons.remove_rounded, onPressed: onRemove),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 26),
            child: Text(
              '${item.qty}',
              textAlign: TextAlign.center,
              style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: Colors.white),
            ),
          ),
          _RoundIcon(icon: Icons.add_rounded, onPressed: onAdd),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white24,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}
