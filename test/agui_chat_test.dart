import 'dart:convert';
import 'dart:io';

import 'package:a2ui_flutter/v0_9/basic_catalog.dart';
import 'package:agentic_client/agentic_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_agui_backend.dart';

/// Lets the real HTTP traffic of the chat run, pumping frames, until
/// [condition] holds.
Future<void> _pumpUntil(WidgetTester tester, bool Function() condition) async {
  for (var i = 0; i < 200 && !condition(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(condition(), isTrue);
}

void main() {
  testWidgets('renders the agent surface and sends its button action back', (tester) async {
    // flutter_test answers every HTTP request with 400; reach the local backend.
    final overrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = overrides);
    final backend = (await tester.runAsync(
      () => FakeAguiBackend.start([
        {'type': 'TEXT_MESSAGE_START', 'messageId': 'm1', 'role': 'assistant'},
        {'type': 'TEXT_MESSAGE_CONTENT', 'messageId': 'm1', 'delta': 'Here is a counter'},
        {'type': 'TEXT_MESSAGE_END', 'messageId': 'm1'},
        {
          'type': 'TOOL_CALL_RESULT',
          'messageId': 'm2',
          'toolCallId': 'c1',
          'content': jsonEncode({
            'a2ui_operations': [
              {
                'createSurface': {'surfaceId': 'counter', 'catalogId': 'test.catalog'},
              },
              {
                'updateComponents': {
                  'surfaceId': 'counter',
                  'components': [
                    {
                      'id': 'root',
                      'component': 'Button',
                      'child': 'label',
                      'action': {
                        'event': {
                          'name': 'increment',
                          'context': {'step': 1},
                        },
                      },
                    },
                    {'id': 'label', 'component': 'Text', 'text': 'Add **one**'},
                  ],
                },
              },
            ],
          }),
        },
      ]),
    ))!;
    addTearDown(() => tester.runAsync(backend.close));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AguiChat(
            baseUrl: backend.baseUrl,
            catalog: basicCatalog().derive(catalogId: 'test.catalog', components: ['Text', 'Button']),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'Show a counter');
    await tester.tap(find.text('Send'));
    await _pumpUntil(tester, () => find.text('Add one').evaluate().isNotEmpty);

    expect(find.text('Here is a counter'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(backend.requests.single['messages'], [containsPair('content', 'Show a counter')]);

    await tester.tap(find.text('Add one'));
    await _pumpUntil(tester, () => backend.requests.length == 2);

    final pendingAction = (backend.requests[1]['forwardedProps'] as Map)['pending_action'] as Map;
    expect(pendingAction['name'], 'increment');
    expect(pendingAction['surfaceId'], 'counter');
    expect(pendingAction['sourceComponentId'], 'root');
    expect(pendingAction['context'], {'step': 1});
  });
}
