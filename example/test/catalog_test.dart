import 'package:a2ui_core/a2ui_core.dart'
    show A2uiRendererAction, A2uiRendererError, MessageProcessor, ValidationConfig;
import 'package:a2ui_flutter/a2ui_flutter.dart';
import 'package:example/catalog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _Harness = ({
  MessageProcessor<ComponentImplementation> processor,
  List<A2uiRendererAction> actions,
  List<A2uiRendererError> errors,
});

/// Renders [components] on a surface of the example catalog, with [data] as
/// the surface's data model.
Future<_Harness> _pumpSurface(
  WidgetTester tester,
  List<Map<String, Object?>> components, {
  Map<String, Object?>? data,
}) async {
  final processor = MessageProcessor<ComponentImplementation>(
    catalogs: [buildExampleCatalog()],
    validationConfig: ValidationConfig.strict,
  );
  addTearDown(processor.dispose);
  final actions = <A2uiRendererAction>[];
  final errors = <A2uiRendererError>[];
  processor.model.onAction.subscribe(actions.add);
  processor.model.onError.subscribe(errors.add);
  processor.processMessages([
    {
      'version': 'v0.9',
      'createSurface': {'surfaceId': 's', 'catalogId': exampleCatalogId},
    },
    if (data != null)
      {
        'version': 'v0.9',
        'updateDataModel': {'surfaceId': 's', 'path': '/', 'value': data},
      },
    {
      'version': 'v0.9',
      'updateComponents': {'surfaceId': 's', 'components': components},
    },
  ]);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: MediaQuery(
          // The test font draws every glyph one em wide, which overflows the
          // fixed-width cart views at the default text scale.
          data: const MediaQueryData(textScaler: TextScaler.linear(0.5)),
          child: SingleChildScrollView(child: A2uiSurface(surface: processor.model.getSurface('s')!)),
        ),
      ),
    ),
  );
  return (processor: processor, actions: actions, errors: errors);
}

void main() {
  testWidgets('renders ProductCard, WeatherTile and Stat, ignoring undeclared properties', (tester) async {
    final harness = await _pumpSurface(tester, [
      {
        'id': 'root',
        'component': 'Column',
        'children': ['product', 'weather', 'stat'],
      },
      {
        'id': 'product',
        'component': 'ProductCard',
        'name': 'Coffee Mug',
        'price': r'$12.99',
        'description': 'Holds coffee.',
        'badge': 'new',
      },
      {'id': 'weather', 'component': 'WeatherTile', 'city': 'Oslo', 'temperature': '4°C', 'condition': 'snowy'},
      {'id': 'stat', 'component': 'Stat', 'label': 'Orders', 'value': '1,284'},
    ]);

    expect(find.text('Coffee Mug'), findsOneWidget);
    expect(find.text(r'$12.99'), findsOneWidget);
    expect(find.text('Holds coffee.'), findsOneWidget);
    expect(find.text('Oslo'), findsOneWidget);
    expect(find.byIcon(Icons.ac_unit), findsOneWidget);
    expect(find.text('1,284'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);
    expect(harness.errors, isEmpty);
  });

  testWidgets('renders UserProfile and MyButton', (tester) async {
    final harness = await _pumpSurface(tester, [
      {
        'id': 'root',
        'component': 'Column',
        'children': ['profile', 'button'],
      },
      {'id': 'profile', 'component': 'UserProfile', 'name': 'Ada', 'email': 'ada@example.com'},
      {'id': 'button', 'component': 'MyButton', 'title': 'Go'},
    ]);

    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('ada@example.com'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsOneWidget);
    expect(harness.errors, isEmpty);
  });

  testWidgets('MyCounter shows the bound count and dispatches increment and decrement', (tester) async {
    final harness = await _pumpSurface(
      tester,
      [
        {
          'id': 'root',
          'component': 'MyCounter',
          'count': {'path': '/count'},
        },
      ],
      data: {'count': 3},
    );
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await tester.tap(find.byIcon(Icons.remove));
    await tester.pump();
    expect([for (final action in harness.actions) action.name], ['increment', 'decrement']);
    expect(harness.actions.first.sourceComponentId, 'root');

    harness.processor.processMessages({
      'version': 'v0.9',
      'updateDataModel': {'surfaceId': 's', 'path': '/count', 'value': 4},
    });
    await tester.pump();
    expect(find.text('4'), findsOneWidget);
    expect(harness.errors, isEmpty);
  });

  testWidgets('CartSelector lists the bound items and dispatches toggleCartItem and cartCheckout', (tester) async {
    final harness = await _pumpSurface(
      tester,
      [
        {
          'id': 'root',
          'component': 'CartSelector',
          'items': {'path': '/items'},
          'total': {'path': '/total'},
        },
      ],
      data: {
        'items': [
          {'id': 'a', 'name': 'Tea', 'price': 1.5, 'selected': true},
          {'id': 'b', 'name': 'Jam', 'price': 2, 'selected': false},
        ],
        'total': r'$1.50',
      },
    );
    expect(find.text('Tea'), findsOneWidget);
    expect(find.text(r'$1.50'), findsWidgets);

    await tester.tap(find.text('Jam'));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect([for (final action in harness.actions) action.name], ['toggleCartItem', 'cartCheckout']);
    expect(harness.actions.first.context, {'item_id': 'b'});
    expect(harness.errors, isEmpty);
  });

  testWidgets('CartSummary pays with its payAction, or cartPay without one', (tester) async {
    final harness = await _pumpSurface(tester, [
      {
        'id': 'root',
        'component': 'Column',
        'children': ['food', 'cart'],
      },
      {
        'id': 'food',
        'component': 'CartSummary',
        'items': [
          {'id': 'p', 'name': 'Pizza', 'price': 9, 'qty': 2},
        ],
        'total': r'$18.00',
        'payAction': 'payOrder',
      },
      {'id': 'cart', 'component': 'CartSummary', 'items': <Object?>[], 'total': r'$0.00'},
    ]);
    expect(find.text('Pizza'), findsOneWidget);

    await tester.tap(find.text(r'Pay $18.00'));
    await tester.tap(find.text(r'Pay $0.00'));
    await tester.pump();
    expect([for (final action in harness.actions) action.name], ['payOrder', 'cartPay']);
    expect(harness.errors, isEmpty);
  });

  testWidgets('RestaurantList and RestaurantMenu dispatch their actions', (tester) async {
    final harness = await _pumpSurface(
      tester,
      [
        {
          'id': 'root',
          'component': 'Column',
          'children': ['list', 'menu'],
        },
        {
          'id': 'list',
          'component': 'RestaurantList',
          'restaurants': {'path': '/restaurants'},
        },
        {
          'id': 'menu',
          'component': 'RestaurantMenu',
          'restaurantName': 'Luigi',
          'items': [
            {'id': 'm1', 'name': 'Soup', 'price': 4, 'qty': 0},
          ],
          'cartCount': {'path': '/cartCount'},
        },
      ],
      data: {
        'restaurants': [
          {'id': 'r1', 'name': 'Luigi', 'cuisine': 'Italian', 'rating': '4.5'},
        ],
        'cartCount': 0,
      },
    );
    expect(find.text('Italian'), findsOneWidget);
    expect(find.text('Soup'), findsOneWidget);

    await tester.tap(find.text('Italian'));
    await tester.tap(find.text('Add'));
    await tester.pump();
    expect([for (final action in harness.actions) action.name], ['selectRestaurant', 'addToCart']);
    expect(harness.actions[0].context, {'restaurant_id': 'r1'});
    expect(harness.actions[1].context, {'item_id': 'm1'});
    expect(harness.errors, isEmpty);
  });
}
