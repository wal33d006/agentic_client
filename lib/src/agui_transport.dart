/// Bridges the AG-UI event stream from our backend into genui's [Transport]
/// interface. The backend emits standard AG-UI events; A2UI ops travel inside
/// `TOOL_CALL_RESULT.content` under the `a2ui_operations` envelope (the
/// CopilotKit convention used by `a2ui.render(...)` on the Python side).
///
/// This adapter:
///   • posts each user message to `${baseUrl}/` via AgUiClient
///   • forwards completed assistant text bubbles to `incomingText`
///   • unwraps `a2ui_operations`, parses each op into an `A2uiMessage`, and
///     pushes them to `incomingMessages` — which genui's SurfaceController
///     consumes to build/update Surfaces
library;

import 'dart:async';
import 'dart:convert';

import 'package:ag_ui/ag_ui.dart' as agui;
import 'package:genai_primitives/genai_primitives.dart' as gp;
import 'package:genui/genui.dart';

class AgUiTransport implements Transport {
  AgUiTransport({required this.baseUrl, this.catalogDescription})
      : _client = agui.AgUiClient(
          config: agui.AgUiClientConfig(baseUrl: baseUrl),
        );

  /// e.g. `http://localhost:8123`. We POST to `$baseUrl/` (trailing slash
  /// — the backend mounts the graph at root).
  final String baseUrl;

  /// Optional free-text description of the catalog we expose to the agent.
  /// The backend's `generate_a2ui` tool reads this from `state.copilotkit.context`
  /// to know which Flutter widgets it can pick. Leave null for fixed-schema
  /// tools (search_flights), which carry their own schema on the backend.
  final String? catalogDescription;

  final agui.AgUiClient _client;
  final _textCtrl = StreamController<String>.broadcast();
  final _msgCtrl = StreamController<A2uiMessage>.broadcast();

  /// Stable per-conversation IDs — keeps the backend's checkpointer happy.
  final String _threadId = 'thread_${DateTime.now().millisecondsSinceEpoch}';

  /// Conversation history — every prior user/assistant turn must be replayed
  /// because the backend agent is stateless across requests (the checkpointer
  /// only persists state, not message history outside the run).
  final List<agui.Message> _history = [];

  @override
  Stream<String> get incomingText => _textCtrl.stream;

  @override
  Stream<A2uiMessage> get incomingMessages => _msgCtrl.stream;

  @override
  Future<void> sendRequest(gp.ChatMessage message) async {
    final userText = message.text;
    if (userText.isEmpty) return;

    _history.add(
      agui.UserMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        content: userText,
      ),
    );

    final input = agui.SimpleRunAgentInput(
      threadId: _threadId,
      runId: 'run_${DateTime.now().millisecondsSinceEpoch}',
      messages: List<agui.Message>.from(_history),
      state: const <String, dynamic>{},
      tools: const [],
      context: _buildContext(),
      forwardedProps: const <String, dynamic>{},
    );

    final assistantText = StringBuffer();
    String? assistantMsgId;
    final toolArgsById = <String, StringBuffer>{};
    final toolNamesById = <String, String>{};

    // Full URL bypasses the package's `${baseUrl}/${endpoint}` concatenation,
    // so we POST to "$baseUrl/" exactly — see backend serve.py:90.
    await for (final event in _client.runAgent('$baseUrl/', input)) {
      switch (event.eventType) {
        case agui.EventType.textMessageStart:
          assistantText.clear();
          final e = event as agui.TextMessageStartEvent;
          assistantMsgId = e.messageId;
        case agui.EventType.textMessageContent:
          final e = event as agui.TextMessageContentEvent;
          assistantText.write(e.delta);
        case agui.EventType.textMessageChunk:
          final e = event as agui.TextMessageChunkEvent;
          if (e.delta != null) assistantText.write(e.delta);
        case agui.EventType.textMessageEnd:
          final text = assistantText.toString();
          if (text.isNotEmpty) {
            _textCtrl.add(text);
            _history.add(
              agui.AssistantMessage(
                id: assistantMsgId ?? 'msg_${DateTime.now().millisecondsSinceEpoch}',
                content: text,
              ),
            );
          }

        case agui.EventType.toolCallStart:
          final e = event as agui.ToolCallStartEvent;
          toolNamesById[e.toolCallId] = e.toolCallName;
          toolArgsById[e.toolCallId] = StringBuffer();
        case agui.EventType.toolCallArgs:
          final e = event as agui.ToolCallArgsEvent;
          toolArgsById.putIfAbsent(e.toolCallId, StringBuffer.new).write(e.delta);
        case agui.EventType.toolCallChunk:
          final e = event as agui.ToolCallChunkEvent;
          if (e.toolCallId != null && e.delta != null) {
            toolArgsById.putIfAbsent(e.toolCallId!, StringBuffer.new).write(e.delta);
          }
        case agui.EventType.toolCallEnd:
          // No-op — args are flushed when the result lands.
          break;

        case agui.EventType.toolCallResult:
          final e = event as agui.ToolCallResultEvent;
          _emitA2uiOpsFromToolResult(e.content);
          // Record the tool call + result in history so follow-up turns can
          // see what the assistant did.
          _history.add(
            agui.ToolMessage(
              id: 'msg_tool_${DateTime.now().millisecondsSinceEpoch}',
              toolCallId: e.toolCallId,
              content: e.content,
            ),
          );

        case agui.EventType.runError:
          final e = event as agui.RunErrorEvent;
          _textCtrl.add('⚠️ ${e.message}');

        default:
          // RUN_STARTED / RUN_FINISHED / STATE_* / STEP_* / etc.
          // Add handlers here when we need them (e.g. STATE_DELTA for the
          // todos pattern).
          break;
      }
    }
  }

  /// Pulls `a2ui_operations` out of a tool result `content` JSON string and
  /// pushes each op into the SurfaceController as an `A2uiMessage`.
  void _emitA2uiOpsFromToolResult(String content) {
    Object? decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      return; // not JSON → not A2UI
    }
    if (decoded is! Map<String, dynamic>) return;
    final ops = decoded['a2ui_operations'];
    if (ops is! List) return;

    for (final op in ops) {
      if (op is! Map<String, dynamic>) continue;
      // A2UI v0.9 ops are tagged with `version: "v0.9"` at the top level.
      final tagged = {'version': 'v0.9', ...op};
      try {
        _msgCtrl.add(A2uiMessage.fromJson(tagged));
      } catch (err, st) {
        // Surface validation errors as a chat bubble so they're visible.
        // Continue with the rest of the ops — one malformed component
        // shouldn't drop the whole surface.
        final hint = _diagnoseBadOp(op);
        _textCtrl.add('⚠️ A2UI parse error: $err${hint == null ? "" : "\n$hint"}');
        // ignore: avoid_print
        print('A2UI parse failed for op $op\n$st');
      }
    }
  }

  /// Best-effort hint about why an op was rejected. The agent's most common
  /// mistakes: uses `type` instead of `component`, wraps properties in `props`,
  /// or invents snake_case component names.
  String? _diagnoseBadOp(Map<String, dynamic> op) {
    final body = op['updateComponents'];
    if (body is! Map) return null;
    final components = body['components'];
    if (components is! List) return null;
    final issues = <String>{};
    for (final c in components) {
      if (c is! Map) continue;
      if (c.containsKey('type') && !c.containsKey('component')) {
        issues.add('uses "type" — must be "component"');
      }
      if (c.containsKey('props')) {
        issues.add('wraps properties under "props" — must be flat');
      }
      final name = (c['component'] ?? c['type']) as Object?;
      if (name is String && name.contains('_')) {
        issues.add('snake_case name "$name" — must be PascalCase');
      }
    }
    return issues.isEmpty ? null : 'hint: ${issues.join("; ")}';
  }

  /// Builds the AG-UI `context` array shipped on each request.
  ///
  /// `LangGraphAGUIAgent.langgraph_default_merge_state` on the backend reads
  /// the top-level AG-UI `context` field and writes it to
  /// `state.copilotkit.context`. That's what the demo agent's `generate_a2ui`
  /// tool reads to learn which Flutter widgets it can emit.
  List<agui.Context> _buildContext() {
    if (catalogDescription == null) return const [];
    return [
      agui.Context(
        description: 'Available A2UI components on this Flutter client.',
        value: catalogDescription!,
      ),
    ];
  }

  @override
  void dispose() {
    _textCtrl.close();
    _msgCtrl.close();
    _client.close();
  }
}
