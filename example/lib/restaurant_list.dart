import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'food_theme.dart';

/// Step 1 of the food-ordering flow.
///
/// Renders the list of restaurants bound to `/restaurants` (a list of
/// `{id, name, cuisine, rating}`). Tapping a row fires a `selectRestaurant`
/// action carrying the restaurant id; the backend opens that restaurant's
/// `RestaurantMenu` (step 2) and seeds the shared selection state.
final _restaurantListSchema = S.object(
  description:
      'Step 1 of the food-ordering flow: a tappable list of restaurants. '
      '`restaurants` is a list of {id, name, cuisine, rating}.',
  properties: {
    'restaurants': A2uiSchemas.listOrReference(
      items: S.object(
        properties: {
          'id': S.string(),
          'name': S.string(),
          'cuisine': S.string(),
          'rating': S.string(),
        },
      ),
    ),
  },
  required: ['restaurants'],
);

final restaurantListItem = CatalogItem(
  name: 'RestaurantList',
  dataSchema: _restaurantListSchema,
  widgetBuilder: (ctx) {
    final data = ctx.data as Map<String, Object?>;
    return BoundList(
      dataContext: ctx.dataContext,
      value: data['restaurants'],
      builder: (context, restaurants) => _RestaurantListView(
        restaurants: _coerceRestaurants(restaurants),
        onSelect: (id) => ctx.dispatchEvent(
          UserActionEvent(
            name: 'selectRestaurant',
            sourceComponentId: ctx.id,
            context: {'restaurant_id': id},
          ),
        ),
      ),
    );
  },
);

class Restaurant {
  const Restaurant({
    required this.id,
    required this.name,
    required this.cuisine,
    required this.rating,
  });

  final String id;
  final String name;
  final String cuisine;
  final String rating;
}

List<Restaurant> _coerceRestaurants(List<Object?>? raw) {
  if (raw == null) return const [];
  return raw.whereType<Map>().map((m) {
    final map = m.cast<String, Object?>();
    return Restaurant(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      cuisine: (map['cuisine'] ?? '').toString(),
      rating: (map['rating'] ?? '').toString(),
    );
  }).toList();
}

class _RestaurantListView extends StatelessWidget {
  const _RestaurantListView({required this.restaurants, required this.onSelect});

  final List<Restaurant> restaurants;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    return FoodCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FoodHeader(
            emoji: '🍴',
            title: 'Pick a restaurant',
            subtitle: 'Tap to see the menu',
            step: '1 of 3',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: Column(
              children: [
                for (var i = 0; i < restaurants.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _RestaurantRow(
                    restaurant: restaurants[i],
                    onTap: () => onSelect(restaurants[i].id),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RestaurantRow extends StatelessWidget {
  const _RestaurantRow({required this.restaurant, required this.onTap});

  final Restaurant restaurant;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: const Color(0xFFFFFBF8),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: FoodTheme.hairline),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              EmojiAvatar(emoji: cuisineEmoji(restaurant.cuisine), size: 48),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      restaurant.name,
                      style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: FoodTheme.ink),
                    ),
                    const SizedBox(height: 3),
                    Text(restaurant.cuisine, style: textTheme.bodySmall?.copyWith(color: FoodTheme.inkSoft)),
                  ],
                ),
              ),
              if (restaurant.rating.isNotEmpty) ...[
                RatingPill(rating: restaurant.rating),
                const SizedBox(width: 6),
              ],
              const Icon(Icons.chevron_right_rounded, color: FoodTheme.inkSoft),
            ],
          ),
        ),
      ),
    );
  }
}
