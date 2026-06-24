/// A small A2UI catalog for the example app.
///
/// Bundles a few `BasicCatalogItems` primitives plus three custom widgets the
/// agent can emit:
///
///   • `ProductCard`  — image, title, price tile
///   • `WeatherTile`  — city, temperature, condition with an icon
///   • `Stat`         — label + big number for KPI-style readouts
library;

import 'package:example/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:genui/genui.dart';
import 'package:json_schema_builder/json_schema_builder.dart';

import 'cart_selector.dart';
import 'cart_summary.dart';
import 'counter.dart';
import 'my_button.dart';
import 'restaurant_list.dart';
import 'restaurant_menu.dart';

const exampleCatalogId = 'copilotkit://app-dashboard-catalog';

/// Free-text spec the agent reads (via AG-UI `context`) to know which
/// components it can emit. Keep it verbose — the secondary LLM uses it
/// verbatim as a system prompt.
const exampleCatalogDescription = '''
You are emitting A2UI v0.9 operations for a Flutter client whose catalogId is
"copilotkit://app-dashboard-catalog".

═══════════ WIRE FORMAT ═══════════

Each component is shaped EXACTLY like:

  { "id": "<unique-id>", "component": "<CatalogName>", <flat properties...> }

Rules (any violation breaks rendering):
  1. The discriminator key is "component" — never "type".
  2. Properties live FLAT on the component — never nested under "props".
  3. Component names are PascalCase — "ProductCard", not "product_card".
  4. Exactly one component must have id "root".
  5. Container children ("Row", "Column") are arrays of component-id strings.

═══════════ COMPONENTS ═══════════

Primitives:
  Text     { text: string, variant?: "h1"|"h2"|"h3"|"h4"|"h5"|"caption"|"body" }
  Column   { children: string[] }
  Row      { children: string[] }
  Divider  {}
  Button   { action: {event: {name: string, context?: object}}, child: string }

═══════════ INTERACTION ═══════════

When the user taps a Button, the client packs the action's `name` and
`context` into `forwarded_props.pending_action` on the next run. The
backend graph reads `state["pending_action"]` and either mutates state
silently (e.g. "increment") or injects a synthetic HumanMessage so you
respond (e.g. "buy").

Common silent action names this backend recognizes:
  - "increment"      → state.counter += 1
  - "decrement"      → state.counter = max(0, state.counter - 1)
  - "toggleTodo"     → flips state.todos[ctx.id].done
  - "toggleCartItem"  → flips selected for state.cart[context.item_id] (step 1)
  - "cartCheckout"    → renders the CartSummary surface (advances to step 2)
  - "cartPay"         → marks the CartSummary as paid
  - "selectRestaurant"→ opens RestaurantMenu for context.restaurant_id
  - "addToCart"       → adds context.item_id to the food cart
  - "removeFromCart"  → decrements context.item_id in the food cart
  - "viewCheckout"    → renders the order CartSummary (advances to checkout)
  - "listRestaurants" → returns to the RestaurantList
  - "payOrder"        → marks the order CartSummary as paid

Pick action names from this set when emitting Buttons. The Button's
`child` is the id of a Text component used as the label.

Custom:
  ProductCard {
    name:        string  (required)
    price:       string  (required, e.g. "\$9.99")
    imageUrl:    string  (optional, https URL)
    description: string  (optional)
  }

  WeatherTile {
    city:        string  (required)
    temperature: string  (required, e.g. "72°F")
    condition:   string  (required, one of: "sunny"|"cloudy"|"rainy"|"snowy")
  }

  Stat {
    label: string  (required)
    value: string  (required, e.g. "1,284")
  }

  CartSelector {            // step 1 of the two-step cart flow
    items: object[]  (required, list of {id, name, price, selected}; bind to /items)
    total: string    (optional, formatted total of selected items; bind to /total)
  }                         // rows fire "toggleCartItem" (context {item_id});
                           // the button fires "cartCheckout"

  CartSummary {            // step 2 — rendered by the backend's cart_checkout
    items:  object[]  (required, selected {id, name, price}; bind to /items)
    total:  string    (required, formatted total; bind to /total)
    status: string    (optional, "pending" | "paid"; bind to /status)
  }                         // the Pay button fires "cartPay"

  Prefer the dedicated build_cart tool to start the cart flow; it renders
  CartSelector and seeds shared state. You normally don't emit these two
  components by hand.

  RestaurantList {         // step 1 of the food-ordering flow
    restaurants: object[]  (required, list of {id, name, cuisine, rating}; bind to /restaurants)
  }                         // rows fire "selectRestaurant" (context {restaurant_id})

  RestaurantMenu {         // step 2 — rendered by select_restaurant
    restaurantName: string   (optional; bind to /restaurantName)
    items:          object[] (required, {id, name, price, qty}; bind to /items)
    cartCount:      string   (optional; bind to /cartCount)
    cartTotal:      string   (optional; bind to /cartTotal)
  }                         // rows fire "addToCart"/"removeFromCart" (context {item_id});
                           // back fires "listRestaurants"; the footer fires "viewCheckout"

  The food checkout reuses CartSummary with item `qty` and payAction="payOrder".
  Prefer the dedicated list_restaurants tool to start this flow; you normally
  don't emit RestaurantList / RestaurantMenu by hand.

═══════════ EXAMPLES ═══════════

(1) Three product cards in a row:

  { "version": "v0.9",
    "createSurface": {
      "surfaceId": "products",
      "catalogId": "copilotkit://app-dashboard-catalog"
    }
  }

  { "version": "v0.9",
    "updateComponents": {
      "surfaceId": "products",
      "components": [
        { "id": "root", "component": "Row",
          "children": ["p1", "p2", "p3"] },
        { "id": "p1", "component": "ProductCard",
          "name": "Coffee Mug", "price": "\$12.99",
          "imageUrl": "https://images.unsplash.com/photo-1514228742587-6b1558fcca3d?w=400" },
        { "id": "p2", "component": "ProductCard",
          "name": "Notebook", "price": "\$8.49",
          "imageUrl": "https://images.unsplash.com/photo-1531346878377-a5be20888e57?w=400" },
        { "id": "p3", "component": "ProductCard",
          "name": "Headphones", "price": "\$59.00",
          "imageUrl": "https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=400" }
      ]
    }
  }

(2) An interactive counter. The displayed value uses a PATH BINDING
    (\`{ "path": "/count" }\`) into the surface's data model so it can be
    updated without re-emitting the components. The backend bumps state on
    each click AND emits an \`updateDataModel\` op for path \`/count\`.

    Initialize the data model with \`count: 0\` via a separate
    \`updateDataModel\` op right after \`createSurface\`. Always use
    surfaceId="counter" for the counter (the backend's ActionMiddleware
    targets that id by default).

  { "version": "v0.9",
    "createSurface": {
      "surfaceId": "counter",
      "catalogId": "copilotkit://app-dashboard-catalog"
    }
  }

  { "version": "v0.9",
    "updateDataModel": {
      "surfaceId": "counter",
      "path": "/count",
      "value": 0
    }
  }

  { "version": "v0.9",
    "updateComponents": {
      "surfaceId": "counter",
      "components": [
        { "id": "root", "component": "Row",
          "children": ["dec", "val", "inc"] },
        { "id": "dec", "component": "Button",
          "action": { "event": { "name": "decrement" } },
          "child": "dec-lbl" },
        { "id": "dec-lbl", "component": "Text", "text": "−" },
        { "id": "val", "component": "Text",
          "text": { "path": "/count" }, "variant": "h3" },
        { "id": "inc", "component": "Button",
          "action": { "event": { "name": "increment" } },
          "child": "inc-lbl" },
        { "id": "inc-lbl", "component": "Text", "text": "+" }
      ]
    }
  }
''';

/// Builds the catalog at startup.
Catalog buildExampleCatalog() {
  return Catalog([
    BasicCatalogItems.text,
    BasicCatalogItems.column,
    BasicCatalogItems.row,
    BasicCatalogItems.divider,
    BasicCatalogItems.list,
    // Interactive: taps fire a UserActionEvent → SurfaceController forwards
    // it through Conversation → AgUiTransport packs it into
    // `forwarded_props.pending_action` for the backend.
    BasicCatalogItems.button,
    userProfileItem,
    buttonItem,
    counterItem,
    // Two-step cart flow: CartSelector (step 1) → CartSummary (step 2),
    // carried across steps by the backend's shared `cart` state.
    cartSelectorItem,
    cartSummaryItem,
    // Food-ordering flow: RestaurantList (step 1) → RestaurantMenu (step 2) →
    // CartSummary (step 3, reused), carried by shared `selected_restaurant_id`
    // and `food_cart` state.
    restaurantListItem,
    restaurantMenuItem,
    _productCard,
    _weatherTile,
    _stat,
  ], catalogId: exampleCatalogId);
}

// ─── ProductCard ────────────────────────────────────────────────────────────

final _productCardSchema = S.object(
  description: 'A product tile with image, name and price.',
  properties: {
    'name': A2uiSchemas.stringReference(),
    'price': A2uiSchemas.stringReference(),
    'description': A2uiSchemas.stringReference(),
    'imageUrl': A2uiSchemas.stringReference(),
  },
  required: ['name', 'price'],
);

final _productCard = CatalogItem(
  name: 'ProductCard',
  dataSchema: _productCardSchema,
  widgetBuilder: (ctx) {
    final data = ctx.data as Map<String, Object?>;
    return BoundString(
      dataContext: ctx.dataContext,
      value: data['name'],
      builder: (context, name) {
        return BoundString(
          dataContext: ctx.dataContext,
          value: data['price'],
          builder: (context, price) {
            return BoundString(
              dataContext: ctx.dataContext,
              value: data['description'],
              builder: (context, description) {
                return BoundString(
                  dataContext: ctx.dataContext,
                  value: data['imageUrl'],
                  builder: (context, imageUrl) {
                    return SizedBox(
                      width: 200,
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (imageUrl != null && imageUrl.isNotEmpty)
                              AspectRatio(
                                aspectRatio: 1,
                                child: Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Container(color: Colors.black12, child: const Icon(Icons.image_not_supported)),
                                ),
                              ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    name ?? '',
                                    style: Theme.of(context).textTheme.titleMedium,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (description != null && description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      description,
                                      style: Theme.of(context).textTheme.bodySmall,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Text(
                                    price ?? '',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      color: Theme.of(context).colorScheme.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
  },
);

// ─── WeatherTile ────────────────────────────────────────────────────────────

final _weatherTileSchema = S.object(
  description: 'A weather summary tile for a single city.',
  properties: {
    'city': A2uiSchemas.stringReference(),
    'temperature': A2uiSchemas.stringReference(),
    'condition': A2uiSchemas.stringReference(),
  },
  required: ['city', 'temperature', 'condition'],
);

final _weatherTile = CatalogItem(
  name: 'WeatherTile',
  dataSchema: _weatherTileSchema,
  widgetBuilder: (ctx) {
    final data = ctx.data as Map<String, Object?>;
    return BoundString(
      dataContext: ctx.dataContext,
      value: data['city'],
      builder: (context, city) {
        return BoundString(
          dataContext: ctx.dataContext,
          value: data['temperature'],
          builder: (context, temperature) {
            return BoundString(
              dataContext: ctx.dataContext,
              value: data['condition'],
              builder: (context, condition) {
                return Container(
                  width: 180,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF42A5F5), Color(0xFF1E88E5)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_weatherIcon(condition), color: Colors.white, size: 36),
                      const SizedBox(height: 12),
                      Text(
                        city ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        temperature ?? '',
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700),
                      ),
                      if (condition != null && condition.isNotEmpty)
                        Text(condition, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
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

IconData _weatherIcon(String? condition) {
  switch (condition?.toLowerCase()) {
    case 'sunny':
      return Icons.wb_sunny;
    case 'cloudy':
      return Icons.cloud;
    case 'rainy':
      return Icons.umbrella;
    case 'snowy':
      return Icons.ac_unit;
    default:
      return Icons.wb_cloudy;
  }
}

// ─── Stat ───────────────────────────────────────────────────────────────────

final _statSchema = S.object(
  description: 'A KPI readout: large value with a small label below.',
  properties: {'label': A2uiSchemas.stringReference(), 'value': A2uiSchemas.stringReference()},
  required: ['label', 'value'],
);

final _stat = CatalogItem(
  name: 'Stat',
  dataSchema: _statSchema,
  widgetBuilder: (ctx) {
    final data = ctx.data as Map<String, Object?>;
    return BoundString(
      dataContext: ctx.dataContext,
      value: data['label'],
      builder: (context, label) {
        return BoundString(
          dataContext: ctx.dataContext,
          value: data['value'],
          builder: (context, value) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value ?? '',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(label ?? '', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            );
          },
        );
      },
    );
  },
);
