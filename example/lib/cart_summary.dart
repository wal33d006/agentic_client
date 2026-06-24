import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'cart_selector.dart' show CartItem;
import 'food_theme.dart';

/// Step 2 of the two-step cart flow.
///
/// A DIFFERENT surface from [cartSelectorItem], rendered by the backend's
/// `cart_checkout` tool out of the items still `selected` in shared state.
/// Shows the order summary + total bound to `/items` and `/total`, plus a
/// sample Pay button that fires `cartPay`. The backend flips `/status` to
/// "paid" on payment, which swaps the button for a confirmation.
final _cartSummarySchema = S.object(
  description:
      'Order summary of the selected items with a total and a sample Pay '
      'button. Used as the checkout step for both the simple cart and the '
      'food-ordering flow. `items` is a list of {id, name, price, qty?}; '
      '`status` is "pending" or "paid"; `payAction` is the action name the '
      'Pay button fires (defaults to "cartPay").',
  properties: {
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
    'total': A2uiSchemas.stringReference(),
    'status': A2uiSchemas.stringReference(),
    'payAction': A2uiSchemas.stringReference(),
  },
  required: ['items', 'total'],
);

final cartSummaryItem = CatalogItem(
  name: 'CartSummary',
  dataSchema: _cartSummarySchema,
  widgetBuilder: (ctx) {
    final data = ctx.data as Map<String, Object?>;
    return BoundList(
      dataContext: ctx.dataContext,
      value: data['items'],
      builder: (context, items) {
        return BoundString(
          dataContext: ctx.dataContext,
          value: data['total'],
          builder: (context, total) {
            return BoundString(
              dataContext: ctx.dataContext,
              value: data['status'],
              builder: (context, status) {
                return BoundString(
                  dataContext: ctx.dataContext,
                  value: data['payAction'],
                  builder: (context, payAction) => _CartSummaryView(
                    items: _coerceItems(items),
                    total: total ?? r'$0.00',
                    paid: status == 'paid',
                    // Defaults to the simple-cart action; the food flow sets
                    // this to "payOrder" so Pay routes to its own backend tool.
                    onPay: () => ctx.dispatchEvent(
                      UserActionEvent(
                        name: (payAction == null || payAction.isEmpty) ? 'cartPay' : payAction,
                        sourceComponentId: ctx.id,
                      ),
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

List<CartItem> _coerceItems(List<Object?>? raw) {
  if (raw == null) return const [];
  return raw.whereType<Map>().map((m) {
    final map = m.cast<String, Object?>();
    return CartItem(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      price: (map['price'] as num?)?.toDouble() ?? 0,
      selected: true,
      qty: (map['qty'] as num?)?.toInt() ?? 1,
    );
  }).toList();
}

class _CartSummaryView extends StatelessWidget {
  const _CartSummaryView({
    required this.items,
    required this.total,
    required this.paid,
    required this.onPay,
  });

  final List<CartItem> items;
  final String total;
  final bool paid;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return FoodCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FoodHeader(
            emoji: paid ? '🎉' : '🧾',
            title: paid ? 'Order confirmed' : 'Your order',
            subtitle: paid ? 'Thanks for ordering!' : 'Review and pay',
            step: '3 of 3',
            gradient: paid ? FoodTheme.successGradient : FoodTheme.appetiteGradient,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              children: [
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        EmojiAvatar(emoji: foodEmoji(item.name), size: 36),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: FoodTheme.avatarBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${item.qty}×',
                            style: textTheme.labelMedium?.copyWith(color: FoodTheme.brandDeep, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.name,
                            style: textTheme.bodyLarge?.copyWith(color: FoodTheme.ink),
                          ),
                        ),
                        Text(
                          item.lineTotalLabel,
                          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: FoodTheme.ink),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16, color: FoodTheme.hairline),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text('Total', style: textTheme.titleMedium?.copyWith(color: FoodTheme.inkSoft)),
                const Spacer(),
                Text(
                  total,
                  style: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: FoodTheme.brandDeep),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: paid
                ? Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: FoodTheme.successGradient),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Payment complete',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ],
                    ),
                  )
                : GradientButton(
                    label: 'Pay $total',
                    icon: Icons.lock_rounded,
                    onPressed: onPay,
                    expand: true,
                  ),
          ),
        ],
      ),
    );
  }
}
