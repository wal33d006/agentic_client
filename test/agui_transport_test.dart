import 'dart:convert';

import 'package:a2ui_core/a2ui_core.dart'
    show A2uiRendererAction, AgentToRendererMessage, CreateSurfaceMessage, UpdateComponentsMessage;
import 'package:agentic_client/agentic_client.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_agui_backend.dart';

Map<String, Object?> _toolResult(Object content) => {
  'type': 'TOOL_CALL_RESULT',
  'messageId': 'm2',
  'toolCallId': 'c1',
  'content': jsonEncode(content),
};

void main() {
  test('emits text and the ops of a tool result as A2UI messages', () async {
    final backend = await FakeAguiBackend.start([
      {'type': 'TEXT_MESSAGE_START', 'messageId': 'm1', 'role': 'assistant'},
      {'type': 'TEXT_MESSAGE_CONTENT', 'messageId': 'm1', 'delta': 'Here you go'},
      {'type': 'TEXT_MESSAGE_END', 'messageId': 'm1'},
      _toolResult({
        'a2ui_operations': [
          {
            'createSurface': {'surfaceId': 'products', 'catalogId': 'my-app.catalog'},
          },
          {
            'updateComponents': {
              'surfaceId': 'products',
              'components': [
                {'id': 'root', 'component': 'Text', 'text': 'Hi'},
              ],
            },
          },
        ],
      }),
    ]);
    addTearDown(backend.close);
    final transport = AgUiTransport(baseUrl: backend.baseUrl);
    addTearDown(transport.dispose);
    final texts = <String>[];
    final messages = <AgentToRendererMessage>[];
    transport.incomingText.listen(texts.add);
    transport.incomingMessages.listen(messages.add);

    await transport.sendRequest('Show me products');

    expect(texts, ['Here you go']);
    expect(messages, [isA<CreateSurfaceMessage>(), isA<UpdateComponentsMessage>()]);
    final create = messages.first as CreateSurfaceMessage;
    expect(create.version, 'v0.9');
    expect(create.surfaceId, 'products');
    expect(create.catalogId, 'my-app.catalog');
    expect(backend.requests.single['messages'], [containsPair('content', 'Show me products')]);
  });

  test('sends an action as forwarded_props.pending_action, outside the history', () async {
    final backend = await FakeAguiBackend.start([]);
    addTearDown(backend.close);
    final transport = AgUiTransport(baseUrl: backend.baseUrl);
    addTearDown(transport.dispose);

    await transport.sendAction(
      A2uiRendererAction(
        name: 'increment',
        surfaceId: 'counter',
        sourceComponentId: 'inc',
        timestamp: DateTime.utc(2026, 1, 2),
        context: {'step': 1},
      ),
    );

    final request = backend.requests.single;
    expect(request['messages'], isEmpty);
    expect(request['forwardedProps'], {
      'pending_action': {
        'name': 'increment',
        'surfaceId': 'counter',
        'sourceComponentId': 'inc',
        'timestamp': '2026-01-02T00:00:00.000Z',
        'context': {'step': 1},
      },
    });
  });

  test('reports an op it cannot parse as text', () async {
    final backend = await FakeAguiBackend.start([
      _toolResult({
        'a2ui_operations': [
          {
            'createSurface': {'surfaceId': 'products'},
          },
        ],
      }),
    ]);
    addTearDown(backend.close);
    final transport = AgUiTransport(baseUrl: backend.baseUrl);
    addTearDown(transport.dispose);
    final texts = <String>[];
    final messages = <AgentToRendererMessage>[];
    transport.incomingText.listen(texts.add);
    transport.incomingMessages.listen(messages.add);

    await transport.sendRequest('Show me products');

    expect(messages, isEmpty);
    expect(texts, [allOf(startsWith('⚠️ A2UI parse error:'), contains('catalogId'))]);
  });
}
